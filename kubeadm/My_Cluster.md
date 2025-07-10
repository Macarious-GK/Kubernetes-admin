# Kubernetes Admin
## Table of Contents

- [Setup Kubeadm CLuster](#setup-kubeadm-cluster)
- [Configure Kubectl to control Remote Cluster](#configure-kubectl-to-control-remote-cluster)
- [Configure NFS Server and Storage Class](#configure-nfs-server-and-storage-class)
- [Accessing Kubernetes Services via NodePort](#accessing-kubernetes-services-via-nodeport)
- [Pod Autoscaling](#pod-autoscaling)
- [CI/CD + GitOps Tasks](#cicd--gitops-tasks)
- [Logging & Monitoring](#logging--monitoring)
- [Accessing Private Container Registry with imagePullSecrets](#accessing-private-container-registry-with-imagepullsecrets)
- [Disaster Recovery & Backup](#disaster-recovery--backup)
- [Multi-Cluster Kubernetes Management with Rancher](#multi-cluster-kubernetes-management-with-rancher)


## Setup Kubeadm Cluster

### Prepare Infra-Machines Networks
> Enable IPv4,IPv6 packet forwarding
```bash
sudo swapoff -a
sudo modprobe br_netfilter
sudo modprobe overlay

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### Install Docker Engine on Ubuntu
> Add Docker's official GPG key:
```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```
> Add the repository to Apt sources:
```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io 
```

### Installing cri-dockerd
```bash
# get version from https://github.com/Mirantis/cri-dockerd/releases/latest
apt-get install ./cri-dockerd-<version>.deb
systemctl status cri-docker
```

### Installing kubeadm, kubelet and kubectl
```bash
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

### Initialize the Kubernetes cluster
```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///var/run/cri-dockerd.sock --v=5 --apiserver-advertise-address=192.168.56.10
--pod-network-cidr= --apiserver-advertise-address= --cri-socket --v=
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Setup Pod_networking

> Installing Addons --> Pod_networking --> cilium

```bash
# Add the Cilium Helm repository and update it
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium-cli
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Install Cilium with Helm
helm install cilium cilium/cilium --version 1.17.4 \
  --namespace kube-system
 cilium status --wait
kubectl -n kube-system scale deployment cilium-operator --replicas=1
```

### Debugging the Cluster or Resting
```bash
sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock
sudo kubeadm reset -f --cri-socket unix:///var/run/crio/crio.sock
sudo kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet ~/.kube /etc/cni/net.d
sudo systemctl restart kubelet cri-docker containerd
```

## Configure Kubectl to control Remote Cluster

### Steps
- Create a private key for the client user (dev)
- Create a certificate signing request
- Sign the request using kubernetes ca.crt
- Secure Copy dev.crt, dev.key, ca.crt to Client 
- @Client Update the kubectl config to use this certificates and keys
- Add Role and RoleBinding in the cluster to give permissions to client

```bash
# @ Master Machine
# Create a private key --> Create a certificate signing request --> Sign the CSR with Kubernetes CA
openssl genrsa -out dev-kary.key 2048
openssl req -new -key dev-kary.key -out dev-kary.csr -subj "/CN=dev-kary/O=dev-group"
sudo openssl x509 -req -in dev-kary.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out dev-kary.crt -days 365
# use client-key-data instead of path
base64 -w 0 /home/vagrant/.kube/certs/dev-kary.key

```
```bash
# @ Dev Machine
mkdir -p ~/.kube
cp /path/to/kubeconfig ~/.kube/config
```
- `kubeconfig file`:
```yaml
apiVersion: v1
kind: Config
clusters:
- name: kary-cluster
  cluster:
    server: https://master:6443
    certificate-authority: /path/to/ca.crt
users:
- name: dev-kary
  user:
    client-certificate: /path/to/client.crt
    client-key: /path/to/client.key
contexts:
- name: my-context
  context:
    cluster: kary-cluster
    user: dev-kary
current-context: my-context
```

## Configure Local provisioner ,NFS Server and Storage Class

### NFS
> Configure NFS Server on Master Machine or Another remote Machine
```bash
# Install NFS-Server
sudo apt install nfs-kernel-server
sudo systemctl start nfs-kernel-server.service

# Create the NFS Directory
sudo mkdir /nfs_shared_folder
chmod 777 /nfs_shared_folder

# Edit /etc/exports
/nfs_shared_folder *(rw,async,no_subtree_check,no_root_squash)

# Apply the new config via:
sudo exportfs -ar

# Install NFS client @ K8s Master Machine & Nodes
sudo apt install nfs-common -y

# Testing the server
sudo mount -t nfs <NFS_SERVER_IP>:/home/youruser/kubedata /mnt
touch /mnt/hello-from-k8s
ls /mnt
sudo umount /mnt
```

> Prepare the Cluster to use NFS for external-provisioner
```bash
# Install external-provisioner using Helm
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace nfs \
    --create-namespace \
    --set nfs.server=192.168.56.13 \
    --set nfs.path=/home/vagrant/nfs_kubedata \
    --set storageClass.name=nfs-storage \
    --set storageClass.defaultClass=true\
```
> Now you can use the nfs-provisioner by defining storageClass.name = nfs-storage in your `PVC`

- [Ex.Provisioner-Reference](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [NFS-Helm-Reference](https://weng-albert.medium.com/how-to-create-an-nfs-storageclass-en-fe962242f44e)


### local-path-provisioner
- Install by kubectl apply
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
```
- https://github.com/rancher/local-path-provisioner

## Accessing Kubernetes Services via NodePort
> Prepare the Master kubeadm Configuration for network access
- kubeadm-config.yaml 
    - `criSocket`: the container runtime Interface used
    - `advertiseAddress`: the IP that the other nodes will use to access the master api-server
    - `node-ip`: the control plane ip 
    - `networking/podSubnet`: The CNI Subnet for PodNetwork

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  # criSocket: unix:///var/run/cri-dockerd.sock
  # criSocket: unix:///var/run/crio/crio.sock
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: "192.168.56.10"
localAPIEndpoint:
  advertiseAddress: "192.168.56.10"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.33.2"
controlPlaneEndpoint: "192.168.56.10"
networking:
  podSubnet: "10.244.0.0/16"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
```
```bash
sudo kubeadm init --config=kubeadm-config.yaml --v=5
# Equivalent kubeadm Command
sudo kubeadm init --control-plane-endpoint=192.168.56.10 \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///var/run/cri-dockerd.sock --v=5 
# Create Token for nodes to join
kubeadm token create --print-join-command
```

> Prepare the Node Configuration for network access
```bash
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=<machine-ip>
EOF

kubeadm join <Master_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash <hash>
```

> Testing
```bash
kubectl create deployment hello --image=nginxdemos/hello
kubectl expose deployment hello --type=NodePort --port=80
curl http://any-node-ip:nodePort    # If using cilium
curl http://node-of-pod:nodePort    # If using flannel

```
- [***kubeadm-config-Reference***](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/)


## Pod Autoscaling 

### HPA

#### Native Metrics Server
1. Install Metrics server 
2. Verify Installation by `kubectl top`
3. Create Deployment, Service, HPA

- Installation
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl edit deployment metrics-server -n kube-system
args:
  - --kubelet-insecure-tls
  - --kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP
kubectl rollout restart deployment metrics-server -n kube-system
kubectl top nodes
kubectl top pod
```

- HPA, Deployment
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 10
      policies:
        - type: Pods
          value: 3
          periodSeconds: 60
        - type: Percent
          value: 100
          periodSeconds: 60
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 30
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
        - type: Percent
          value: 50
          periodSeconds: 60
      selectPolicy: Min
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: php-apache
  template:
    metadata:
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: k8s.gcr.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 300m
            memory: 128Mi

```

#### Custom Metrics Server
- Install the prometheus metrics server
- custom storageClass to local-path, NFS
- Access Prometheus SVC
- Install Prometheus Adaptor
- Install Grafana

- > Prometheus metrics server
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus \
  --namespace prometheus 
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePort=32001 \
  --values prom-values.yaml
```

- `prom-values.yaml`:
```yaml
server:
  persistentVolume:
    enabled: true
    storageClass: local-path
    size: 8Gi

alertmanager:
  persistentVolume:
    enabled: true
    storageClass: local-path
    size: 2Gi
```

- > Expose prometheus
```bash
kubectl port-forward -n prometheus svc/prometheus-server 9090:80
# Incase you want to access another interface
sudo socat TCP-LISTEN:9091,fork TCP:127.0.0.1:9090
```

- > Prometheus adaptor
```bash
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.url=http://prometheus-server.prometheus.svc.cluster.local \
  --set prometheus.port=80 \
  --set rules.default=true
```

- > For Visualization
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana \
  --namespace prometheus \
  --create-namespace \
  --set adminPassword='admin' \
  --set service.type=NodePort \
  --set service.nodePort=32000 \
  --set persistence.enabled=true \
  --set persistence.size=2Gi \
  --set persistence.storageClassName=local-path
```

https://medium.com/@mjkool/metrics-server-in-kubernetes-0ba52352ddcd
https://sleeplessbeastie.eu/2023/12/06/how-to-install-metrics-server/
https://github.com/kubernetes-sigs/metrics-server

---

### VPA

## CI/CD + GitOps Tasks

## Jenkins use Kubernets pods as agents
- Prerequisite
  - Setup a kubeadm cluster and expose the control plan url 
  - First Install Kubernetes plugin in jenkins
- Steps
  - `[Jenkins Controller]`:: Choose configure cloud --> Kubernetes
  - `[Jenkins Controller]`:: Copy Kubernetes server ca.crt to configuration
  - `[Jenkins Controller]`:: Put control plane URL, Namespace
  - `[Jenkins Controller]`:: Choose WebSocket Connection between pods --> Jenkins
  - `[Kubernetes Server]`:: create a namespace for jenkins
  - `[Kubernetes Server]`:: Create Service account & Token
  - `[Kubernetes Server]`:: Create Role & Rolebinding for this serviceaccount 
  - `[Kubernetes Server]`:: Give the sufficient permissions for the role so jenkins agent can perform its tasks 
```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-serviceaccount
  namespace: jenkins

---
# ServiceAccount Secret Token
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-service-account-token
  annotations:
    kubernetes.io/service-account.name: jenkins-serviceaccount
type: kubernetes.io/service-account-token

---
# role.yaml
# apiVersion: rbac.authorization.k8s.io/v1
# kind: Role
# metadata:
#   name: jenkins-role
#   namespace: jenkins
# rules:
# - apiGroups: [""]
#   resources: ["pods", "services", "endpoints", "persistentvolumeclaims"]
#   verbs: ["get", "watch", "list", "create", "delete"]
# - apiGroups: ["apps"]
#   resources: ["deployments", "replicasets"]
#   verbs: ["get", "watch", "list", "create", "delete"]
# - apiGroups: ["batch"]
#   resources: ["jobs", "cronjobs"]
#   verbs: ["get", "watch", "list", "create", "delete"]

---
# rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-binding
  namespace: jenkins
subjects:
- kind: ServiceAccount
  name: jenkins-serviceaccount  
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl cluster-info
kubectl create ns jenkins
kubectl create serviceaccount jenkins --namespace=jenkins
kubectl get secret jenkins-service-account-token -o jsonpath='{.data.token}' | base64 --decode
kubectl create rolebinding jenkins-admin-binding --clusterrole=admin --serviceaccount=jenkins:jenkins --namespace=jenkins
```
---

## Logging & Monitoring

## policy enforcement kubernetes

## Accessing Private Container Registry with imagePullSecrets
```bash
kubectl create secret docker-registry regcred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=username \
  --docker-password=pass \
  --docker-email=emai@.com
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hostname-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hostname-web 
  template:
    metadata:
      labels:
        app: hostname-web
    spec:
      containers:
      - name: hostname-web
        image: macarious25siv/private-docker-repo:python-pod-name-app
        ports:
        - containerPort: 8080
      imagePullSecrets:
      - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: hostname-web
spec:
  selector:
    app: hostname-web
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
      nodePort: 30255
  type: NodePort

```
https://earthly.dev/blog/private-docker-registry/

https://www.digitalocean.com/community/tutorials/how-to-set-up-a-private-docker-registry-on-ubuntu-22-04

## Disaster Recovery & Backup

## Multi-Cluster Kubernetes Management with Rancher

apiVersion: v1
kind: Service
metadata:
  annotations:
    meta.helm.sh/release-name: prometheus
    meta.helm.sh/release-namespace: prometheus
  labels:
    app.kubernetes.io/component: server
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: prometheus
    app.kubernetes.io/version: v3.1.0
    helm.sh/chart: prometheus-26.1.0
  name: prometheus-server
  namespace: prometheus
  resourceVersion: "129912"
  uid: e3b6c02c-1290-4c5e-80f3-dda49f34ff34
spec:
  clusterIP: 10.104.47.112
  clusterIPs:
  - 10.104.47.112
  internalTrafficPolicy: Cluster
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 9090
    nodePort: 30080
  selector:
    app.kubernetes.io/component: server
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/name: prometheus
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
                      

