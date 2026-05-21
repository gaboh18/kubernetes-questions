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

## Q1 - API Server Hardening
**Task:** Edit `/opt/cks-lab/kube-apiserver.yaml` to set `--anonymous-auth` and `--profiling` to `false`.

**Solution:** 

```bash
vi /opt/cks-lab/kube-apiserver.yaml 
# Change true to false
```

---

## Q2 - Kubelet Hardening
** Task: Edit `/opt/cks-lab/kubelet-config.yaml` to change authorization mode from `AlwaysAllow` to `Webhook`.

** Solution:**
```bash
vi /opt/cks-lab/kubelet-config.yaml 
# Change mode: AlwaysAllow to mode: Webhook
```

---

## Q3 - RBAC Least Privilege
**Task: User `dev-user` is bound to `cluster-admin` via 'overly-permissive'. Delete this binding and create 'dev-view-binding' granting the 'view' clusterrole instead.

** Solution:
```bash
kubectl delete crb overly-permissive
kubectl create crb dev-view-binding --clusterrole=view --user=dev-user
```

---

## Q4 - ServiceAccount Tokens
**Task: Disable `automountServiceAccountToken` on Deployment `vault-reader` in namespace `alpha`.

**Solution: 
```bash
kubectl edit deploy vault-reader -n alpha 
# Add automountServiceAccountToken: false under spec.template.spec
```

---

## Q5 - AppArmor Profile
**Task: Apply the AppArmor profile 'localhost/restricted-profile' to the container 'nginx' in Deployment `apparmor-app` (namespace `alpha`) using an annotation.

**Solution:
```bash
kubectl edit deploy apparmor-app -n alpha
# Add under spec.template.metadata.annotations:
 container.apparmor.security.beta.kubernetes.io/nginx: localhost/restricted-profile
```

---

## Q6 - Seccomp Profile
**Task: Enforce the 'RuntimeDefault' seccomp profile at the Pod level for Deployment `seccomp-app` (namespace `alpha`).

**Solution:
```bash
kubectl edit deploy seccomp-app -n alpha
# Add under spec.template.spec.securityContext:
 seccompProfile:
   type: RuntimeDefault
```

---

## Q7 - Node Hardening (Docker Daemon)
**Task: Remove the insecure TCP socket (`0.0.0.0:2375`) from `/opt/cks-lab/daemon.json`.

**Solution: 
```bash
vi /opt/cks-lab/daemon.json 
# Delete the tcp://0.0.0.0:2375 entry from the array
```

---

## Q8 - Kubesec Pod Hardening
**Task: Modify Deployment `kubesec-app` (namespace `beta`) to `runAsNonRoot: true` (Pod level) and `readOnlyRootFilesystem: true` (Container level).

**Solution:
```bash
kubectl edit deploy kubesec-app -n beta
```

---

## Q9 - Encryption at Rest
**Task: Add `--encryption-provider-config=/opt/cks-lab/encryption-config.yaml` to the API server manifest.

**Solution:
```bash
vi /opt/cks-lab/kube-apiserver.yaml
```

---

## Q10 - ImagePolicyWebhook
**Task:** Add `ImagePolicyWebhook` to the `--enable-admission-plugins` flag and specify `--admission-control-config-file=/opt/cks-lab/admission-config.yaml` in the API Server.

**Solution: 
```bash
vi /opt/cks-lab/kube-apiserver.yaml
```

---

## Q11 - Trivy Vulnerability Fix
**Task: Deployment `frontend-app` (namespace `beta`) is running `nginx:1.14`. Update it to `nginx:alpine` to fix CVEs.

**Solution:
```bash
kubectl set image deploy/frontend-app nginx=nginx:alpine -n beta
```

---

## Q12 - OPA Gatekeeper Simulation
**Task:** Label namespace `gamma` with `gatekeeper=enforce` to activate an existing policy.

**Solution:
```bash
kubectl label ns gamma gatekeeper=enforce
```

---

## Q13 - Audit Logging
**Task: Add `--audit-policy-file=/opt/cks-lab/audit-policy.yaml` and `--audit-log-path=/var/log/kubernetes/audit.log` to the API server.

**Solution: 
```bash
vi /opt/cks-lab/kube-apiserver.yaml
```

---

## Q14 - Runtime Security / Investigation
**Task: A malicious pod (`hacker-pod`) is running in namespace `beta`. Delete it.

**Solution:
```bash
kubectl delete pod hacker-pod -n beta
```

---

## Q15 - Dropping Capabilities
**Task: Drop ALL capabilities for the container in Deployment `kubesec-app` (namespace `beta`).

**Solution: 
```bash
kubectl edit deploy kubesec-app -n beta
# Add to container securityContext:
 capabilities:
   drop: ["ALL"]
```

---

## Q16 - Network Policy: Default Deny (5 pts)
**Task: Create a NetworkPolicy named 'default-deny' in namespace `secure-zone` that blocks all Ingress and Egress traffic.

**Solution:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: secure-zone
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF
```

---

## Q17 - Network Policy: DNS Trap (5 pts)
**Task: NetworkPolicy `egress-trap` in namespace `gamma` breaks DNS resolution. Edit it to allow Egress on TCP/UDP port 53.

**Solution: 
```bash
kubectl edit netpol egress-trap -n gamma
# Add ports to egress block:
- ports:
  - port: 53
    protocol: UDP
  - port: 53
    protocol: TCP
```
