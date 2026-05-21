#!/bin/bash
# exam-cleanup.sh - Tears down the mock environment for the CKS Simulator

echo "Cleaning up CKS Simulator Environment..."

rm -rf /opt/cks-lab/
rm -f /etc/kubernetes/manifests/kube-apiserver.yaml
rm -f /var/log/falco.log
rm -f /var/lib/kubelet/config.yaml

# Clean Namespaces & Resources
kubectl delete ns backend web app istio-system prod frontend database dmz --ignore-not-found=true
kubectl delete pod immutable-pod -n default --ignore-not-found=true

# Clean CRDs
kubectl delete crd ciliumnetworkpolicies.cilium.io --ignore-not-found=true
kubectl delete crd peerauthentications.security.istio.io --ignore-not-found=true

if [ -f .timer_pid ]; then
    kill $(cat .timer_pid) 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "Cleanup complete."
