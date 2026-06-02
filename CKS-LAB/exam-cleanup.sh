#!/bin/bash
# exam-cleanup.sh - Robust CKS Environment Teardown

echo "Cleaning up CKS Simulator Environment..."

# 1. Clear Jumpbox Files (Mac Host)
rm -rf /opt/cks-lab/* 2>/dev/null

# 2. Clean up Live Resources with Strict Fail-Fast Timeouts
echo "Removing Kubernetes resources..."
kubectl delete ns backend web app istio-system prod frontend database dmz --ignore-not-found=true --timeout=5s 2>/dev/null
kubectl delete pod immutable-pod -n default --ignore-not-found=true --timeout=5s 2>/dev/null
kubectl delete crd ciliumnetworkpolicies.cilium.io peerauthentications.security.istio.io --ignore-not-found=true --timeout=5s 2>/dev/null

# clean node-level injections
echo "Reverting Node-level misconfigurations..."
minikube ssh "sudo rm -rf /etc/kubernetes/image-config /etc/kubernetes/audit /etc/kubernetes/encryption"
minikube ssh "sudo rm -f /etc/apparmor.d/custom-profile"

echo "✅ Cleanup complete."
