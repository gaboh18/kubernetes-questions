#!/bin/bash
# exam-cleanup.sh - CKS Simulator Cleanup

echo "🧹 Cleaning up CKS resources..."

NAMESPACES="net-block runtime-sec istio-prod"
for ns in $NAMESPACES; do
    kubectl delete ns "$ns" --grace-period=0 --force --wait=false 2>/dev/null
done

kubectl delete deploy restricted-deploy token-deploy --grace-period=0 --force 2>/dev/null
kubectl delete pod webapp-pod --grace-period=0 --force 2>/dev/null

sudo rm -rf /opt/cks-lab

if [ -f .timer_pid ]; then
    PID=$(cat .timer_pid)
    kill $PID 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "✨ System Clean."
