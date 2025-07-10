#!/bin/bash

set -e
KUBERNETES_VERSION="1.33"
sudo sed -i 's/^#\$nrconf{restart} =.*/\$nrconf{restart} = "a";/' /etc/needrestart/needrestart.conf
# --------------------------------------------------

# Install required packages
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https containerd
echo "\e[36m********************************************************************\e[0m"
echo -e "\e[32m[INFO] Installing containerd...\e[0m"
# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
    echo "[ERROR] Failed to configure containerd with SystemdCgroup = true."
    exit 1
fi
echo "\e[32m[INFO] Containerd installed and configured.\e[0m"
echo "\e[36m********************************************************************\e[0m"
# Disable swap and configure sysctl
echo "\e[32m[INFO] Disabling swap and setting up sysctl...\e[0m"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

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
echo "\e[36m********************************************************************\e[0m"
# Install Kubernetes packages
echo "\e[32m[INFO] Installing kubeadm, kubelet...\e[0m"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm
sudo apt-mark hold kubelet kubeadm
sudo systemctl enable --now kubelet
echo "\e[36m********************************************************************\e[0m"

################################################################## Node
# Configure kubelet node IP (optional for multi-interface hosts)
echo "\e[32m[INFO] Configuring kubelet with node IP...\e[0m"
NODE_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^10\." | grep -v "^127\." | head -n 1)

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF

sudo systemctl daemon-reexec
sudo systemctl restart kubelet
echo "[Info] Node is ready to join the cluster using the kubeadm join command."

echo "\e[36m********************************************************************\e[0m"
if [ -f /vagrant/scripts/kubeadm-join.sh ]; then
    echo "[INFO] Found kubeadm-join.sh script. Please run it to join the cluster."
    echo "Run the following command to join the cluster:"
    echo "sudo /vagrant/scripts/kubeadm-join.sh"

else
    echo "[WARNING] kubeadm-join.sh script not found. You may need to create it manually."
fi

echo "\e[32m[SUCCESS] Worker node setup complete.\e[0m"
echo "\e[36m********************************************************************\e[0m"
