#!/bin/bash
# exam-cleanup.sh - Lab 2 Synchronized (Includes Q17)

echo "🧹 Cleaning up Kubernetes resources..."

# 1. Namespaces (The only ones used in Lab 2)
NAMESPACES="audit monitoring network-demo prod"
for ns in $NAMESPACES; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
        echo "Deleting namespace: $ns"
        kubectl delete ns "$ns" --grace-period=0 --force --wait=false 2>/dev/null
    fi
done

# 2. Global/Default Namespace Resources
echo "Removing deployments and services..."
kubectl delete deploy secret-api-deploy canary-main-app web-app-canary rolling-update-app readiness-api-deploy security-context-app selector-fix-deploy nodeport-api-deploy ingress-web-deploy broken-app --grace-period=0 --force 2>/dev/null

kubectl delete svc canary-service web-svc api-nodeport web-svc-ingress 2>/dev/null
kubectl delete cj backup-job 2>/dev/null
kubectl delete ingress web-ingress api-ingress 2>/dev/null
kubectl delete secret db-credentials 2>/dev/null

# 3. Local Files (Now includes Q17 OCI files)
echo "Clearing temporary lab files..."
rm -rf /tmp/app-source /tmp/my-app.tar /tmp/broken-deploy.yaml /tmp/fix-ingress.yaml /tmp/oci-lab /tmp/internal-tool-oci.tar 2>/dev/null

# (Optional) Clean up the local docker images built during the lab
# docker rmi my-app:1.0 internal-tool:v1.2 2>/dev/null

# 4. Timer Cleanup
if [ -f .timer_pid ]; then
    PID=$(cat .timer_pid)
    kill $PID 2>/dev/null
    rm .timer_pid .remaining_time 2>/dev/null
fi

echo "⏳ Waiting for namespaces to fully clear..."
while [ $(kubectl get ns | grep -E "audit|monitoring|network-demo|prod" | wc -l) -gt 0 ]; do
    printf "."
    sleep 2
done

echo -e "\n✨ System is fresh and clean!"
