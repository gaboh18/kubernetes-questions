# Hints and example solutions

Try [TASKS.md](TASKS.md) first. Use the wrapper to avoid changing your active cluster. These examples cover the automatically checked tasks; the advanced tasks need the prerequisites and manual evidence described in TASKS.md.

## Q3: default isolation

```bash
./k8s-sim.sh kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
YAML
```

NetworkPolicies are additive. Check other policies and prove enforcement with real traffic.

## Q7: final image user

Before the final CMD, add to `.cks-state/jumpbox/Dockerfile`:

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1000
USER appuser
```

The static check does not build the image. Build it in a disposable environment and verify UID 1000.

## Q10 and Q16: recreate immutable Pod specifications

Use a trusted SBOM tool to scan the image, and validate its output before saving `/opt/cks-lab/sbom.spdx` inside the lab node. No BOM executable is downloaded automatically, and a blank file is insufficient.

Export the relevant Pod, remove server-generated metadata and `status`, change its container list or securityContext, then recreate that named Pod in `default`. Deleting/recreating a Pod interrupts it; only do this to the disposable exercise object. For Q10 retain `good-app` and remove `vulnerable-app`. For Q16 retain the sleeping busybox process and add:

```yaml
securityContext:
  readOnlyRootFilesystem: true
```

Wait for Ready and inspect the application state. An nginx container can fail with a read-only root filesystem unless required writable locations are provided; this fixture deliberately uses a sleeping process.

## Q11: Pod Security Admission

```bash
./k8s-sim.sh kubectl label namespace frontend pod-security.kubernetes.io/enforce=restricted --overwrite
```

For repeatable exercises pin `pod-security.kubernetes.io/enforce-version` to your cluster's minor version. Test admission with both compliant and violating Pods; a label does not remediate existing running Pods.

## Q12: explicit token projection

```bash
./k8s-sim.sh kubectl patch serviceaccount db-sa -n database --type=merge -p '{"automountServiceAccountToken":false}'
./k8s-sim.sh kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: token-pod
  namespace: database
spec:
  serviceAccountName: db-sa
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: token-vol
      mountPath: /var/run/secrets/tokens
      readOnly: true
  volumes:
  - name: token-vol
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 7200
          audience: api
YAML
./k8s-sim.sh kubectl wait --for=condition=Ready pod/token-pod -n database --timeout=180s
```

## Q14: checksum fixture

```bash
./k8s-sim.sh ssh
cd /opt/cks-lab
sha512sum -c kube-apiserver-test.sha512
# After confirming a checksum mismatch for this exact test file:
rm -- kube-apiserver-test
exit
```

Keep the checksum file. The fixture first hashes trusted content, then changes it, producing a real mismatch rather than a malformed checksum error.

## Q15: historical rollout drill

```bash
./k8s-sim.sh kubectl set image deployment/web-server httpd=httpd:2.4.58 -n dmz
./k8s-sim.sh kubectl rollout status deployment/web-server -n dmz --timeout=180s
```

Use scanner results and current vendor guidance to choose images for actual deployments; these tags only preserve the historical exercise.

## Q18: TLS pair

```bash
./k8s-sim.sh kubectl create secret tls secure-tls --cert=.cks-state/jumpbox/tls.crt --key=.cks-state/jumpbox/tls.key -n default
```

## Q21: scan artifact

Install Trivy separately from its official distribution, then:

```bash
trivy image --severity CRITICAL --format json --output .cks-state/jumpbox/trivy-report.json httpd:2.4.49
```

A failed database download or image fetch is not a successful scan. Review the report, image identity and findings; its existence alone is not evidence.

## Q22: least privilege

```bash
./k8s-sim.sh kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: auditor
  namespace: rbac
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
YAML
./k8s-sim.sh kubectl auth can-i get pods -n rbac --as=system:serviceaccount:rbac:auditor
./k8s-sim.sh kubectl auth can-i get secrets -n rbac --as=system:serviceaccount:rbac:auditor
./k8s-sim.sh kubectl auth can-i create pods -n rbac --as=system:serviceaccount:rbac:auditor
```

Expect yes, no, no. Inspect the RoleBinding and other bindings for additional privileges.

## Advanced corrections

For Q4, use parentheses: `(open_read or open_write) and fd.name = "/dev/mem"`. Validate with the installed Falco version and replay appropriate events in a disposable runtime lab; the grouping prevents unrelated reads matching the first branch. This detects opens represented by these macros, not every possible memory read/write.

For Q9, Webhook authorization and disabling anonymous authentication solve different problems; configure and test both.

For Q13, `rules: [{level: Metadata}]` is a basic all-request policy. Refine and test policy ordering, secret exposure and retention against the actual requirement.

For Q17, enabling a provider alone does not encrypt previously stored Secrets. On a separate disposable cluster, migrate existing resources and inspect raw etcd bytes, preserving all keys required for decryption.
