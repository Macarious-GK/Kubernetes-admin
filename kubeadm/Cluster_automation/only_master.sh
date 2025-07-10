#!/bin/bash

set -e

KUBERNETES_VERSION=$(kubeadm version | grep 'GitVersion' | sed -E 's/.*GitVersion:"(v[0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
CNI_PLUGIN="flannel"
MASTER_IP="192.168.56.10"
PODSUBNET="10.244.0.0/16"

#----------------------------------- Suppress service restart prompts
sudo sed -i 's/^#\$nrconf{restart} =.*/\$nrconf{restart} = "a";/' /etc/needrestart/needrestart.conf

# ----------------------------------- Create kubeadm-config.yaml 

cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: "${MASTER_IP}"
localAPIEndpoint:
  advertiseAddress: "${MASTER_IP}"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "${KUBERNETES_VERSION}"
controlPlaneEndpoint: "${MASTER_IP}"
networking:
  podSubnet: "${PODSUBNET}"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

echo -e "\e[32m[INFO] kubeadm-config.yaml created.\e[0m"

# ----------------------------------- Initialize Kubernetes master node
echo -e "\e[34m[INFO] Initializing Kubernetes master node...\e[0m"
if [[ ! -f ./kubeadm-config.yaml ]]; then
    echo -e "\e[31m[ERROR] kubeadm-config.yaml not found. Please create it before running this script.\e[0m"
    exit 1
fi
sudo kubeadm init --config=kubeadm-config.yaml --v=5

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
echo -e "\e[32m[SUCCESS] Kubernetes master node initialized.\e[0m"

# Set up the CNI network plugin (Flannel)
echo -e "\e[34m[INFO] Setting up CNI network plugin ...\e[0m"
if [[ "$CNI_PLUGIN" == "flannel" ]]; then
    echo -e "\e[34m[INFO] Applying CNI network plugin flannel...\e[0m"
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    echo -e "\e[32m[SUCCESS] CNI network plugin flannel applied.\e[0m"

elif [[ "$CNI_PLUGIN" == "cilium" ]]; then
    echo -e "\e[34m[INFO] Setting up CNI network plugin (cilium)...\e[0m"
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

    cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList='{10.244.0.0/16}'
    echo -e "\e[32m[SUCCESS] CNI network plugin cilium applied.\e[0m"

else
    echo -e "\e[31m[ERROR] Unsupported CNI plugin: $CNI_PLUGIN. Please use 'flannel' or 'cilium'.\e[0m"
    exit 1
fi

#----------------------------------- Wait for master node to be ready
echo -e "\e[34m[INFO] Waiting for master node to be ready...\e[0m"
while [[ $(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    echo -e "\e[33m[INFO] Still waiting for master node to be ready...\e[0m"
    sleep 5
done
echo -e "\e[32m[SUCCESS] Master node is ready.\e[0m"

# ----------------------------------- prepare kubeadm-join.sh script
echo -e "\e[34m[INFO] Preparing kubeadm-join.sh script...\e[0m"
sudo mkdir -p /vagrant/scripts
JOIN_COMMAND=$(kubeadm token create --print-join-command)
cat <<EOF | sudo tee /vagrant/scripts/kubeadm-join.sh > /dev/null
#!/bin/bash
set -e
sudo $JOIN_COMMAND
EOF
sudo chmod +x /vagrant/scripts/kubeadm-join.sh
echo -e "\e[32m[SUCCESS] kubeadm-join.sh script prepared with actual join command.\e[0m"

#----------------------------------- Clean
UP Restore Default interactive config 
rm kubeadm-config.yaml
sudo sed -i 's/^\$nrconf{restart} = "a";/#\$nrconf{restart} = "i";/' /etc/needrestart/needrestart.conf
echo -e "\e[32m[SUCCESS] Setup complete.\e[0m"
