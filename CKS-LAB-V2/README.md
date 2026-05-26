# 🔒 CKS Simulator - Version 2 (16 Questions)

> **Disclaimer:** To protect your host, control plane files in this simulator are located in `/opt/cks-lab-v2/` instead of `/etc/kubernetes/`.

---

## Q1 - Fix insecure kubelet and etcd
**Task:** Edit `/opt/cks-lab-v2/kubelet-config.yaml` to set `anonymous-auth` to false and `authorization-mode` to `Webhook`. 
**Solution:**
```bash
vi /opt/cks-lab-v2/kubelet-config.yaml
```

# Change authentication.anonymous.enabled to false
# Change authorization.mode to Webhook

## Q2 - TLS Secret
** Task: Create a TLS secret named tls-secret in the default namespace using any dummy certs.
** Solution:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=my-app"
kubectl create secret tls tls-secret --cert=/tmp/tls.crt --key=/tmp/tls.key
```

## Q3 - Dockerfile & Deployment Security
** Task: Edit /tmp/cks-q3/Dockerfile to use USER nobody. Then, edit deployment docker-deploy to enforce: runAsUser: 65535, readOnlyRootFilesystem: true, privileged: false.
** Solution:

```bash
vi /tmp/cks-q3/Dockerfile # Replace USER root with USER nobody
kubectl edit deploy docker-deploy
# Add under spec.template.spec: securityContext: runAsUser: 65535
# Add under spec.template.spec.containers[0]: securityContext: readOnlyRootFilesystem: true, privileged: false
```

## Q4 - Pod accessing /dev/mem
** Task: Identify the pod accessing /dev/mem (hint: mem-hacker). Scale its deployment down to 0 to neutralize it. Write a hypothetical Falco rule (just mental notes, simulator checks the scale).
** Solution:

```bash
kubectl scale deploy mem-hacker --replicas=0
```

## Q5 - Container Security Context Immutability
** Task: Enforce immutability on Deployment immutable-deploy (runAsUser: 30000, readOnlyRootFilesystem: true, allowPrivilegeEscalation: false).
** Solution:

```bash
kubectl edit deploy immutable-deploy
# Add pod securityContext: runAsUser: 30000
# Add container securityContext: readOnlyRootFilesystem: true, allowPrivilegeEscalation: false
```

## Q6 - Audit Logging Retention
** Task: Configure API Server /opt/cks-lab-v2/kube-apiserver.yaml to retain a maximum of 2 log files for 30 days.
** Solution:

```bash
vi /opt/cks-lab-v2/kube-apiserver.yaml
# Add to command: 
# - --audit-log-maxbackup=2
# - --audit-log-maxage=30
```
## Q7 - NetworkPolicy
** Task: In namespace qa, create a policy named deny-and-allow that denies all ingress by default, but allows ingress from pods in the frontend-ns namespace.
**Solution:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-and-allow, namespace: qa }
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: frontend-ns } }
EOF
```
## Q8 - Expose HTTPS via Ingress
** Task: Create an ingress https-ingress for service https-app using tls-secret. It must redirect HTTP to HTTPS.
** Solution:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: https-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts: [my-app.com]
    secretName: tls-secret
  rules:
  - host: my-app.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: https-app, port: { number: 80 } } }
EOF
```

## Q9 - Disable API credential auto-mounting
** Task: Disable auto-mounting for ServiceAccount vault-sa. Modify vault-sa-deploy to mount a projected token manually.
** Solution:

```bash
kubectl patch sa vault-sa -p '{"automountServiceAccountToken": false}'
kubectl edit deploy vault-sa-deploy
# Add to pod spec:
# volumes:
# - name: token-vol
#   projected:
#     sources: [{ serviceAccountToken: { path: token } }]
```

## Q10 - Upgrade cluster node
** Task: Drain node01 (if it exists in your local cluster) to prepare for an upgrade.
** Solution:

```bash
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data --force
# Proceed with apt upgrade kubeadm, kubelet, kubectl manually.
```

## Q11 - Generate SPDX document
** Task: Identify the container in crypto-pod using Alpine. Generate an SPDX document to /tmp/cks-q3/alpine.spdx (mock output). Remove the container.
** Solution:

```bash
touch /tmp/cks-q3/alpine.spdx # Simulating bom generate
kubectl get pod crypto-pod -o yaml > /tmp/crypto.yaml
vi /tmp/crypto.yaml # Delete libcrypto-container
kubectl replace --force -f /tmp/crypto.yaml
```

## Q12 - Restricted Pod Security Standard
** Task: Namespace restricted-ns enforces PSS. Fix violator-deploy so it scales successfully.
** Solution:

```bash
kubectl edit deploy violator-deploy -n restricted-ns
# Add securityContext elements necessary for restricted PSS:
# runAsNonRoot: true
# seccompProfile: { type: RuntimeDefault }
# allowPrivilegeEscalation: false
# capabilities: { drop: [ALL] }
```

## Q13 - Secure Docker daemon
** Task: Remove devuser from the docker group in /opt/cks-lab-v2/group. Ensure /opt/cks-lab-v2/docker.sock is owned by root.
** Solution:

```bash
vi /opt/cks-lab-v2/group # Delete devuser
sudo chown root /opt/cks-lab-v2/docker.sock
```

## Q14 - Cilium Network Policy
** Task: Write a simulated CiliumNetworkPolicy to /opt/cks-lab-v2/cilium-policy.yaml.
** Solution:
```bash
cat <<EOF > /opt/cks-lab-v2/cilium-policy.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata: { name: "secure-app" }
EOF
```


## Q15 - ImagePolicyWebhook
** Task: In /opt/cks-lab-v2/admission-config.yaml, change the default action when the backend is unavailable to deny.
** Solution:

```bash
vi /opt/cks-lab-v2/admission-config.yaml
# Change defaultAllow: true to defaultAllow: false
```

## Q16 - API server authentication
** Task: Fix /opt/cks-lab-v2/kube-apiserver.yaml. Set anonymous-auth=false, authorization-mode=Node,RBAC, and enable NodeRestriction.
** Solution:

```bash
vi /opt/cks-lab-v2/kube-apiserver.yaml
# Update the specific flags.
```
