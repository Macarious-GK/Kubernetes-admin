#!/bin/bash
: <<'BLOCK_COMMENT'
This automation script is designed to setup the VMs that will used to run kubeadm cluster.
-> Define Variables
    1. KUBERNETES_VERSION - Version of Kubernetes to install
    2. CNI_PLUGIN - CNI plugin to use (flannel or cilium)
    3. MASTER_IP - IP address of the master node
    4. PODSUBNET - Pod network CIDR for the cluster
-> Configure kubeadm
    1. Create kubeadm-config.yaml with the necessary configurations
    2. Run kubeadm init with the configuration file
    3. Set up the CNI network plugin
    4. Wait for master node to be ready
    5. Prepare kubeadm-join.sh script with the join command
-> Clean up
BLOCK_COMMENT
set -e
# --------------------------- Configure kubelet node IP 

echo "\e[32m[INFO] Configuring kubelet with node IP...\e[0m"
NODE_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^10\." | grep -v "^127\." | head -n 1)

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF

sudo systemctl daemon-reexec
sudo systemctl restart kubelet
echo "[Info] Node is ready to join the cluster"

# ----------------------------------- Start setup 
if [ -f /vagrant/scripts/kubeadm-join.sh ]; then
    echo "[INFO] Found kubeadm-join.sh script. Please run it to join the cluster."
    echo "Run the following command to join the cluster:"
    echo "sudo /vagrant/scripts/kubeadm-join.sh"
else
    echo "[WARNING] kubeadm-join.sh script not found. You may need to create it manually."
fi

echo "\e[32m[SUCCESS] Worker node Joined the cluster complete.\e[0m"
