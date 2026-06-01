#!/bin/bash
# exam-cleanup.sh - Tears down the Minikube CKS Environment

echo "Cleaning up CKS Simulator Environment..."

# 1. Clean up Jumpbox directory (Mac)
# Using sudo just in case you accidentally created root-owned files during practice
sudo rm -rf /opt/cks-lab/* 2>/dev/null

# 2. Clean up Live Namespaces & Resources
echo "Removing Kubernetes resources..."
kubectl delete ns backend web app istio-system prod frontend database dmz --ignore-not-found=true
kubectl delete pod immutable-pod -n default --ignore-not-found=true

# 3. Clean up CRDs
kubectl delete crd ciliumnetworkpolicies.cilium.io --ignore-not-found=true
kubectl delete crd peerauthentications.security.istio.io --ignore-not-found=true

# 4. Clean up Node-Level Injections (Minikube)
echo "Reverting Node-level misconfigurations..."
# Revert Kubelet authorization mode back to Webhook
minikube ssh "sudo sed -i 's/mode: AlwaysAllow/mode: Webhook/g' /var/lib/kubelet/config.yaml"
minikube ssh "sudo systemctl restart kubelet"

# Remove the compromised binaries
minikube ssh "sudo rm -f /usr/local/bin/kube-apiserver-test*"

# 5. Stop the Timer
if [ -f .timer_pid ]; then
    kill $(cat .timer_pid) 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "✅ Cleanup complete."
