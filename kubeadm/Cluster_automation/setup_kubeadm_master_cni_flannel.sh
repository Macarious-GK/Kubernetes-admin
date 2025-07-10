#!/bin/bash

set -e

KUBERNETES_VERSION="1.33"

#----------------------------------- Suppress service restart prompts
sudo sed -i 's/^#\$nrconf{restart} =.*/\$nrconf{restart} = "a";/' /etc/needrestart/needrestart.conf

# ---------------------------------- Start setup
echo -e "\e[34m[INFO] Updating and installing dependencies...\e[0m"
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https containerd

# ----------------------------------- Configure containerd
echo -e "\e[34m[INFO] Installing and configuring containerd...\e[0m"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
    echo -e "\e[31m[ERROR] Failed to configure containerd with SystemdCgroup = true.\e[0m"
    exit 1
fi
echo -e "\e[32m[SUCCESS] Containerd installed and configured.\e[0m"

# ----------------------------------- Disable swap and configure sysctl
echo -e "\e[34m[INFO] Disabling swap and setting up sysctl...\e[0m"
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

# ----------------------------------- Install Kubernetes components
echo -e "\e[34m[INFO] Installing kubeadm, kubelet, and kubectl...\e[0m"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
echo -e "\e[32m[SUCCESS] Kubernetes packages installed.\e[0m"

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

# ----------------------------------- Set up the CNI network plugin 
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

#----------------------------------- CleanUP Restore Default interactive config 
rm kubeadm-config.yaml
sudo sed -i 's/^\$nrconf{restart} = "a";/#\$nrconf{restart} = "i";/' /etc/needrestart/needrestart.conf
echo -e "\e[32m[SUCCESS] Setup complete.\e[0m"
