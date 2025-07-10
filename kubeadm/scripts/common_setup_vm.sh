#!/bin/bash
: <<'BLOCK_COMMENT'
This automation script is designed to setup the VMs that will used to run kubeadm cluster.
-> Install CRI
    1. Installing containerd
    2. Configure containerd to use systemd cgroup driver
    3. Set the sandbox image to pause:3.10
    4. Enable and start containerd service
-> Prepare Infra-Machines Networks
    1. Disable Swap for kubelet to work properly
    2. Enable br_netfilter and overlay modules
    3. Enable IPv4,IPv6 packet forwarding
    4. Configure sysctl settings for Kubernetes networking
-> Install kubeadm, kubelet, kubectl
    1. Add Kubernetes GPG key
    2. Add the repository to Apt sources
    3. Install kubeadm, kubelet
    4. Hold kubeadm, kubelet packages
-> Install Helm
    1. Install Helm
BLOCK_COMMENT


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

# ----------------------------------- Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

#----------------------------------- Restore Default interactive config 

sudo sed -i 's/^\$nrconf{restart} = "a";/#\$nrconf{restart} = "i";/' /etc/needrestart/needrestart.conf
echo -e "\e[32m[SUCCESS] Setup complete.\e[0m"
