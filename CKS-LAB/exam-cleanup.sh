#!/bin/bash
# exam-cleanup.sh - Tears down the Docker Desktop mock environment

echo "Cleaning up CKS Simulator Environment..."

# Clean up simulated directory
rm -rf /opt/cks-lab/* 2>/dev/null

# Clean up Live Namespaces & Resources
kubectl delete ns backend web app istio-system prod frontend database dmz --ignore-not-found=true
kubectl delete pod immutable-pod -n default --ignore-not-found=true

# Clean up CRDs
kubectl delete crd ciliumnetworkpolicies.cilium.io --ignore-not-found=true
kubectl delete crd peerauthentications.security.istio.io --ignore-not-found=true

if [ -f .timer_pid ]; then
    kill $(cat .timer_pid) 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "✅ Cleanup complete."
