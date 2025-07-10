#===================================Enable IPv4,IPv6     packet forwarding
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

#====================================Install Docker Engine on Ubuntu & CRI 
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#=====================================Installing cri-dockerd
# get version from https://github.com/Mirantis/cri-dockerd/releases/latest
apt-get install ./cri-dockerd-<version>.deb
systemctl status cri-docker

#=====================================Installing kubeadm, kubelet and kubectl
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

#=====================================Initialize the Kubernetes cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///var/run/cri-dockerd.sock --v=5 --apiserver-advertise-address=192.168.56.10
--pod-network-cidr= --apiserver-advertise-address= --cri-socket --v=
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#=====================================Installing Addons --> Pod_networking --> cilium
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

#=====================================Installing Addons --> Pod_networking --> calico
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///var/run/cri-dockerd.sock --v=5 --apiserver-advertise-address=192.168.56.10
curl https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/calico.yaml -O
kubectl apply -f calico.yaml

#=====================================Managing the cluster nodes
kubectl get nodes
kubectl get pods -n kube-system
sudo systemctl status kubelet
#=====================================Joining worker nodes to the cluster
kubeadm token create --print-join-command
--cri-socket unix:///var/run/cri-dockerd.sock
# Edit 
nano /etc/default/kubelet
echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--node-ip=machine-ip-address"'
 | sudo tee /etc/systemd/system/kubelet.service.d/20-nodeip.conf

sudo kubeadm join 192.168.56.10:6443 --cri-socket unix:///var/run/cri-dockerd.sock --token  --discovery-token-ca-cert-hash 
#=====================================Reset the cluster
sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet ~/.kube /etc/cni/net.d
sudo systemctl restart cri-docker
sudo systemctl restart kubelet cri-docker


sudo systemctl stop kubelet

#=====================================Debugging the kube-apiserver container
sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock

rm -rf $HOME/.kube
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /etc/kubernetes

sudo systemctl restart kubelet
sudo systemctl restart containerd  # or your runtime

sudo crictl ps -a | grep kube-apiserver
kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule-



#=====================================Configuring the systemd cgroup driver {Incase of containerd}
sudo nano /etc/containerd/config.toml
```
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  sandbox_image = "registry.k8s.io/pause:3.10"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```
sudo systemctl restart containerd


sudo kubeadm init --config=kubeadm-config.yaml --v=5
- cat kubeadm-config.yaml 
```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/cri-dockerd.sock
  kubeletExtraArgs:
    node-ip: "192.168.56.10"
localAPIEndpoint:
  advertiseAddress: "192.168.56.10"
  bindPort: 6443

---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.32.5"
controlPlaneEndpoint: "192.168.56.10"
networking:
  podSubnet: "10.244.0.0/16"

```


#=====================================References
####### Kubernetes Cluster Setup with kubeadm
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

####### Container Runtimes Engine and Interface
# https://v1-32.docs.kubernetes.io/docs/setup/production-environment/container-runtimes/
# |--> https://docs.docker.com/engine/install/ubuntu/
# |--> https://mirantis.github.io/cri-dockerd/usage/install/

####### Pod Networking
# https://docs.cilium.io/en/stable/installation/k8s-install-helm/
# https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/