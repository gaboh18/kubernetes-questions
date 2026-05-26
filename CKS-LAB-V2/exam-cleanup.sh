#!/bin/bash
# exam-cleanup.sh - CKS Simulator Version 2

echo "🧹 Cleaning up..."

NAMESPACES="qa frontend-ns restricted-ns"
for ns in $NAMESPACES; do
    kubectl delete ns "$ns" --grace-period=0 --force --wait=false 2>/dev/null
done

kubectl delete deploy web-tls docker-deploy mem-hacker immutable-deploy https-app vault-sa-deploy --grace-period=0 --force 2>/dev/null
kubectl delete pod crypto-pod --grace-period=0 --force 2>/dev/null
kubectl delete sa vault-sa 2>/dev/null
kubectl delete secret tls-secret 2>/dev/null
kubectl delete ingress https-ingress 2>/dev/null

sudo rm -rf /opt/cks-lab-v2
rm -f /tmp/cks-q3/alpine.spdx 2>/dev/null

if [ -f .timer_pid ]; then
    PID=$(cat .timer_pid)
    kill $PID 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "✨ System Clean."
