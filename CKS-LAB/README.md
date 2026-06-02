```bash

                                            ,--,                              
                  ,--.                   ,---.'|                              
  ,----..     ,--/  /| .--.--.           |   | :      ,---,           ,---,.  
 /   /   \ ,---,': / '/  /    '.         :   : |     '  .' \        ,'  .'  \ 
|   :     ::   : '/ /|  :  /`. /         |   ' :    /  ;    '.    ,---.' .' | 
.   |  ;. /|   '   , ;  |  |--`          ;   ; '   :  :       \   |   |  |: | 
.   ; /--` '   |  /  |  :  ;_            '   | |__ :  |   /\   \  :   :  :  / 
;   | ;    |   ;  ;   \  \    `.         |   | :.'||  :  ' ;.   : :   |    ;  
|   : |    :   '   \   `----.   \        '   :    ;|  |  ;/  \   \|   :     \ 
.   | '___ |   |    '  __ \  \  |        |   |  ./ '  :  | \  \ ,'|   |   . | 
'   ; : .'|'   : |.  \/  /`--'  /        ;   : ;   |  |  '  '--'  '   :  '; | 
'   | '/  :|   | '_\.'--'.     /         |   ,/    |  :  :        |   |  | ;  
|   :    / '   : |     `--'---'          '---'     |  | ,'        |   :   /   
 \   \ .'  ;   |,'                                 `--''          |   | ,'    
  `---`    '---'                                                  `----'      
                                                                              
                                                                                               
```
---

> **Disclaimer:** To protect your host system, control plane files are simulated in `/opt/cks-lab/`.

---

## Q1 - Admission Controller
**Task:** The cluster's API server is currently missing critical admission control plugins, leaving it vulnerable to unauthorized node updates and untested container images. Ensure that both the `NodeRestriction` and `ImagePolicyWebhook` plugins are actively enforced on the control plane node. An exam-grade admission file has been pre-staged for you at `/etc/kubernetes/image-config/admission-configuration.yaml`. Ensure the API server is running and healthy after applying your changes.

**Solution**:
```bash
# 1. Edit the pre-staged config to enforce strict security (change defaultAllow: true to false)
vi /etc/kubernetes/image-config/admission-configuration.yaml

# 2. Modify the API Server Manifest
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add/Modify under spec.containers.command:
# - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
# - --admission-control-config-file=/etc/kubernetes/image-config/admission-configuration.yaml
# Ensure volumeMounts and volumes mapping /etc/kubernetes/image-config/ are active.
```

---

## Q2 - Kubeadm Upgrade
**Task: Upgrade the control plane node components (`kubeadm`, `kubelet`, `kubectl`) from `v1.30.0` to `v1.30.1`.

**Solution**:

```bash
apt-mark unhold kubeadm kubectl kubelet
apt-get update && apt-get install -y kubeadm=1.30.1-1.1
kubeadm upgrade apply v1.30.1
apt-get install -y kubelet=1.30.1-1.1 kubectl=1.30.1-1.1
systemctl daemon-reload && systemctl restart kubelet
```

---

## Q3 - Network Policy
**Task:** Create a NetworkPolicy named `default-deny-all` in the `backend` namespace that denies all ingress and egress traffic by default.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

---

## Q4 - Falco Runtime Security
**Task:** Review the Falco logs at /opt/cks-lab/falco.log. Identify the pod in the web namespace that spawned a terminal shell (/bin/bash) and delete it..

**Solution:**
```bash
cat /opt/cks-lab/falco.log | grep "Notice A shell was spawned in a container"
# Extract the malicious pod name (hacker-pod)
kubectl delete pod hacker-pod -n web
```

---

## Q5 - Cilium Network Policy
**Task:** Create a `CiliumNetworkPolicy` named `restrict-dns` in the `app` namespace that only allows egress traffic on port 53 (UDP) to `kube-dns`.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: restrict-dns
  namespace: app
spec:
  endpointSelector: {}
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s:k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
EOF
```

---

## Q6 - Istio mTLS
**Task:** Apply a `PeerAuthentication` policy in the `istio-system` namespace to enforce `STRICT` mutual TLS (mTLS) for the entire cluster.

**Solution:** 
```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict-mtls
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
```

---

## Q7 - Dockerfile Security
**Task:** Inspect the Dockerfile at `/opt/cks-lab/Dockerfile`. Modify it so the container runs as a non-root user `appuser` (UID 1000) instead of root.

**Solution:** 
```bash
vi /opt/cks-lab/Dockerfile
# Add the following lines before CMD/ENTRYPOINT:
# RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
# USER appuser
```

---

## Q8 - AppArmor & Seccomp
**Task:** Edit Deployment secure-app in namespace prod. Apply the pre-staged AppArmor profile (custom-profile) via annotations and the RuntimeDefault Seccomp profile via the pod's security context.
(Note: You must load the staged profile at /etc/apparmor.d/custom-profile into the node kernel first).

**Solution:** 
```bash
# 1. Load the profile into the kernel (Run inside minikube ssh as root):
apparmor_parser -q /etc/apparmor.d/custom-profile

# 2. Configure the Deployment (Run on your Mac terminal):
kubectl edit deploy secure-app -n prod
# Add under spec.template.metadata.annotations:
#   container.apparmor.security.beta.kubernetes.io/secure-app: localhost/custom-profile
# Add under spec.template.spec.securityContext:
#   seccompProfile:
#     type: RuntimeDefault
```

---

## Q9 - Kube-bench Fixes
**Task:** A recent security audit revealed a critical vulnerability on the master node: the Kubelet is currently permitting unauthorized API requests. Reconfigure the node's Kubelet to delegate authorization to the Kubernetes API server via Webhooks. Ensure the Kubelet service successfully restarts.

**Solution:**
```bash
vi /var/lib/kubelet/config.yaml
# Change authorization.mode from AlwaysAllow to Webhook:
# authorization:
#   mode: Webhook
systemctl restart kubelet
```

---

## Q10 - SBOM (Software Bill of Materials)
**Task:** Generate an SBOM in SPDX JSON format for the image `nginx:1.24` and save it to `/opt/cks-lab/nginx-sbom.json` using `trivy`.

**Solution:** 
```bash
trivy image --format spdx-json --output /opt/cks-lab/nginx-sbom.json nginx:1.24
```

---

## Q11 - Pod Security Standards (PSS)
**Task:** Enforce the `restricted` Pod Security Standard in the `frontend` namespace at the `enforce` level.

**Solution:**
```bash
kubectl label ns frontend pod-security.kubernetes.io/enforce=restricted
```

---

## Q12 - ServiceAccount Token
**Task:** Modify the ServiceAccount `db-sa` in the `database` namespace so that it no longer automounts API tokens into pods by default.

**Solution:** 
```bash
kubectl edit sa db-sa -n database
# Add the following line:
# automountServiceAccountToken: false
```

---

## Q13 - Auditing
**Task:** The security compliance team requires API server requests to be audited. An audit policy file has already been staged on the control plane node at /etc/kubernetes/audit-policy.yaml. Configure the API server to use this policy file.
(Note: For the scope of this simulation task, you only need to provide the flag pointing to the policy; you do not need to configure the log output destination or volume mounts).

**Solution:** 
```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add the following flags:
# - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
# - --audit-log-path=/var/log/k8s/audit.log
# - --audit-log-maxage=30
# (Ensure volume mounts for these paths are also configured)
```

---

## Q14 - SHA512SUM Verification
**Task:** The incident response team suspects a binary replacement attack has occurred on the master node. A test binary named kube-apiserver-test and its expected SHA512 checksum file (kube-apiserver-test.sha512) are located in the /usr/local/bin/ directory on the node. Verify the integrity of the binary. If the hash does not match the provided checksum, permanently remove the compromised binary from the host.

**Solution:** 
```bash
cd /usr/local/bin/
sha512sum -c kube-apiserver-test.sha512
# If the verification output displays "FAILED", delete it:
rm -f kube-apiserver-test*
```

---

## Q15 - Trivy Image Scan
**Task:** Scan the image `httpd:2.4.49` for CRITICAL vulnerabilities using `trivy`. Update the `web-server` deployment in the `dmz` namespace to `httpd:2.4.58` to resolve them.

**Solution:** 
```bash
trivy image --severity CRITICAL httpd:2.4.49
kubectl set image deploy/web-server httpd=httpd:2.4.58 -n dmz
```

---

## Q16 - RootOnlyFileSystem
**Task:** Modify the Pod `immutable-pod` in the `default` namespace to ensure its root filesystem is mounted as read-only.

**Solution:** 
```bash
# Note: Pod configurations are immutable. You must copy, modify, and replace it.
kubectl get pod immutable-pod -o json > pod.json
vi pod.json
# Under spec.containers[0].securityContext, add:
# readOnlyRootFilesystem: true
kubectl delete pod immutable-pod --force
kubectl apply -f pod.json && rm pod.json
```

---

## Q17 - Secrets Encryption at Rest
**Task:** Kubernetes Secrets are currently being stored in plaintext within etcd. Secure the cluster by ensuring the API server is properly configured to encrypt secrets at rest using the pre-staged template configuration found at /etc/kubernetes/encryption/encryption-config.yaml.
(Note: You must generate a random base64 32-byte key, add it to the secret box inside the config, and wire it up to the API server).

**Solution:** 
```bash
# 1. Generate the key
head -c 32 /dev/urandom | base64

# 2. Populate the key inside /etc/kubernetes/encryption/encryption-config.yaml
vi /etc/kubernetes/encryption/encryption-config.yaml
# Change identity: {} provider to a secretbox provider containing your generated key.

# 3. Reference the configuration file in the API Server
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add the flag:
# - --encryption-provider-config=/etc/kubernetes/encryption/encryption-config.yaml
# Ensure volumeMounts and volumes for /etc/kubernetes/encryption are configured.
```
