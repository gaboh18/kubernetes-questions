#!/bin/bash

echo "🚀 Setting up the environment..."

# --- Infrastructure ---
echo "⏳ Ensuring clean slate..."
# Added 'default' to the list to ensure we clear any non-namespaced resources too
NAMESPACES="audit monitoring network-demo prod"

while [ $(kubectl get ns | grep -E "$(echo $NAMESPACES | tr ' ' '|')" | grep -c "Terminating") -gt 0 ]; do
    echo "Stale namespaces are still terminating... waiting 2s"
    sleep 2
done

echo "🚀 Creating namespaces..."
for ns in $NAMESPACES; do
    kubectl create ns $ns 2>/dev/null
done

# --- UNIQUE SCENARIOS ---

# Q1: Secret Trap (Target: secret-api-deploy)
kubectl create deploy secret-api-deploy --image=nginx --port=80
kubectl set env deploy secret-api-deploy DB_USER=admin DB_PASS=Secret123!

# Q2: CronJob (No setup needed, student creates from scratch)

# Q3: Audit Failure (Target: Pod/log-collector)
kubectl run log-collector -n audit --image=busybox -- /bin/sh -c "while true; do echo 'User \"system:serviceaccount:audit:default\" cannot list pods'; sleep 10; done"

# Q4: Monitoring Setup (Target: Pod/metrics-pod)
kubectl create sa monitor-sa -n monitoring
kubectl create sa wrong-sa -n monitoring
kubectl create sa admin-sa -n monitoring

# Roles and Bindings (with decoys)
kubectl create role metrics-reader -n monitoring --verb=get,list,watch --resource=pods
kubectl create role full-access -n monitoring --verb="*" --resource="*"
kubectl create role view-only -n monitoring --verb=get,list --resource=services

kubectl create rolebinding monitor-binding -n monitoring --role=metrics-reader --serviceaccount=monitoring:monitor-sa
kubectl create rolebinding admin-binding -n monitoring --role=full-access --serviceaccount=monitoring:admin-sa

# 💥 THE FIX: A pod that actively tries to query the API using the wrong SA
kubectl run metrics-pod -n monitoring --image=bitnami/kubectl:latest --overrides='{"spec":{"serviceAccountName":"wrong-sa"}}' -- /bin/sh -c "while true; do kubectl get pods; sleep 5; done"

# Q5: Docker Source (Path check)
mkdir -p /tmp/app-source
cat <<EOF > /tmp/app-source/Dockerfile
FROM busybox
CMD ["echo", "Hello CKAD"]
EOF

# Q6: Canary Base (Target: canary-main-app)
# Renamed to avoid collision with Q12
kubectl create deploy canary-main-app --image=nginx:1.16 --replicas=5
kubectl label deploy canary-main-app app=webapp version=v1 --overwrite
kubectl expose deploy canary-main-app --name=canary-service --port=80

# Q7: NetPol Trap (network-demo)
kubectl run frontend -n network-demo --image=nginx --labels=role=wrong-frontend
kubectl run backend -n network-demo --image=nginx --labels=role=wrong-backend
kubectl run database -n network-demo --image=nginx --labels=role=wrong-db
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: network-demo }
spec: { podSelector: {}, policyTypes: [Ingress] }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend-to-backend, namespace: network-demo }
spec:
  podSelector: { matchLabels: { role: backend } }
  ingress: [{ from: [{ podSelector: { matchLabels: { role: frontend } } }] }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-backend-to-db, namespace: network-demo }
spec:
  podSelector: { matchLabels: { role: db } }
  ingress: [{ from: [{ podSelector: { matchLabels: { role: backend } } }] }]
EOF

# Q8: Broken YAML
cat <<EOF > /tmp/broken-deploy.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata: { name: broken-app }
spec:
  template:
    metadata: { labels: { app: myapp } }
    spec:
      containers: [{ name: web, image: nginx }]
EOF

# Q9: Rollout Base (Target: rolling-update-app)
kubectl create deploy rolling-update-app --image=nginx:1.20

# Q10: Readiness Base (Target: readiness-api-deploy)
kubectl create deploy readiness-api-deploy --image=nginx:latest --port=8080

# Q11: SecContext Base (Target: security-context-app)
kubectl create deploy security-context-app --image=nginx

# Q12: Svc Selector Trap (Target: selector-fix-deploy)
kubectl create deploy selector-fix-deploy --image=nginx --port=80
kubectl label deploy selector-fix-deploy app=webapp tier=frontend --overwrite
kubectl create svc clusterip web-svc --tcp=80:80
kubectl patch svc web-svc -p '{"spec":{"selector":{"app":"wrongapp"}}}'

# Q13: NodePort Base (Target: nodeport-api-deploy)
kubectl create deploy nodeport-api-deploy --image=nginx --port=9090
kubectl label deploy nodeport-api-deploy app=api --overwrite

# Q14/Q15: Ingress Base (Target: ingress-web-deploy)
kubectl create deploy ingress-web-deploy --image=nginx --port=8080
kubectl label deploy ingress-web-deploy app=web
kubectl create svc clusterip web-svc-ingress --tcp=8080:8080
# Fixed path typo /temp to /tmp
cat <<EOF > /tmp/fix-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: api-ingress }
spec:
  rules:
  - http:
      paths:
      - path: /api
        pathType: InvalidType
        backend: { service: { name: api-svc, port: { number: 8080 } } }
EOF

# Q16: Quota Math Setup
kubectl create quota prod-quota -n prod --hard=limits.cpu=2,limits.memory=4Gi

# Q17: OCI export Setup
mkdir -p /tmp/oci-lab
cat <<EOF > /tmp/oci-lab/Dockerfile
FROM alpine:3.18
RUN echo "OCI-Compliant-Layer" > /metadata.txt
CMD ["cat", "/metadata.txt"] 
EOF

echo "✅ Environment Ready! All resource names are unique."
