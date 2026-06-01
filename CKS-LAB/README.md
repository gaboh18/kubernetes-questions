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
**Task:** The cluster's API server is currently missing critical admission control plugins, leaving it vulnerable to unauthorized node updates and untested container images. Ensure that both the NodeRestriction and ImagePolicyWebhook plugins are actively enforced on the control plane node. Ensure the API server is running and healthy after applying your changes.

**Solution**:
```bash
vi /opt/cks-lab/kube-apiserver.yaml 
# Modify --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
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
**Task:** Review the Falco logs at `/var/log/falco.log`. Identify the pod in the `web` namespace that spawned a terminal shell (`/bin/bash`) and delete it.

**Solution:**
```bash
cat /var/log/falco.log | grep "Notice A shell was spawned in a container"
# Extract the pod name (e.g., hacker-pod)
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
**Task:** Edit Deployment `secure-app` in namespace `prod`. Apply the `localhost/custom-profile` AppArmor profile via annotations and the `RuntimeDefault` Seccomp profile via the security context.

**Solution:** 
```bash
kubectl edit deploy secure-app -n prod
# Add under metadata.annotations:
#   container.apparmor.security.beta.kubernetes.io/container-name: localhost/custom-profile
# Add under spec.template.spec.securityContext:
#   seccompProfile:
#     type: RuntimeDefault
```

---

## Q9 - Kube-bench Fixes
**Task:** A recent security audit revealed a critical vulnerability on the master node: the Kubelet is currently permitting unauthorized API requests. Reconfigure the node's Kubelet to delegate authorization to the Kubernetes API server via Webhooks. Ensure the Kubelet service successfully restarts and the node returns to a Ready state..

**Solution:**
```bash
kube-bench run --targets master,node
vi /var/lib/kubelet/config.yaml
# Change authorization: mode: AlwaysAllow to mode: Webhook
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
# Assuming files are in /opt/cks-lab/
cd /opt/cks-lab/
sha512sum -c kube-apiserver.sha512
# If the output says "FAILED", delete it:
rm kube-apiserver
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
kubectl edit pod immutable-pod
# Add to the container's securityContext:
# securityContext:
#   readOnlyRootFilesystem: true
```

---

## Q17 - Secrets Encryption at Rest
**Task:** Kubernetes Secrets are currently being stored in plaintext within etcd. Secure the cluster by ensuring the API server is properly configured to encrypt secrets at rest. You must append the appropriate flag to the API server configuration to enable an encryption provider.
(Note: Assume the provider configuration file is already staged and mapped; you only need to provide the activation flag).

**Solution:** 
```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add the flag:
# - --encryption-provider-config=/etc/kubernetes/enc/encryption.yaml
# (Ensure volume mounts for /etc/kubernetes/enc are configured)
```
