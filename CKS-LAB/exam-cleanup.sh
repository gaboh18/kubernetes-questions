#!/bin/bash
# exam-cleanup.sh - Robust CKS Environment Teardown

echo "Cleaning up CKS Simulator Environment..."

rm -rf /opt/cks-lab/* 2>/dev/null

echo "Removing Kubernetes resources..."
kubectl delete ns backend web app istio-system prod frontend database dmz --ignore-not-found=true --timeout=5s 2>/dev/null
kubectl delete pod immutable-pod multi-pod token-pod -n default --ignore-not-found=true --timeout=5s 2>/dev/null
kubectl delete ingress secure-ingress -n default --ignore-not-found=true 2>/dev/null
kubectl delete secret secure-tls -n default --ignore-not-found=true 2>/dev/null
kubectl delete crd ciliumnetworkpolicies.cilium.io peerauthentications.security.istio.io --ignore-not-found=true --timeout=5s 2>/dev/null

echo "Reverting Node-level injections..."
minikube ssh "sudo rm -rf /etc/kubernetes/image-config /etc/kubernetes/audit /etc/kubernetes/encryption /etc/falco"
minikube ssh "sudo rm -f /etc/apparmor.d/custom-profile /usr/local/bin/bom /usr/local/bin/kube-apiserver-test*"
minikube ssh "sudo gpasswd -d unauthorized_user docker 2>/dev/null; sudo userdel unauthorized_user 2>/dev/null; sudo chown root:docker /var/run/docker.sock 2>/dev/null"

echo "✅ Cleanup complete."
