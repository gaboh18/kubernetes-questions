# CKS mock: 16 tasks, 120 minutes

These are newly written exercises inspired by the topic coverage of [this candidate's report](https://www.reddit.com/r/KubernetesCerts/comments/1rzoh2s/passed_cks_heres_what_actually_came_up/), checked against public documentation on 31 October 2026. The post is anecdotal and does not establish the questions or exact settings on your future exam. Weights below are training weights, not official question weights.

From `secon_version`, start a fresh owned profile with `./k8s-sim.sh start`. The launcher uses the shared runtime in the parent `CKS-LAB` directory; artifact paths below are relative to that parent directory. Existing profiles are not reused. A two-node Docker/Calico cluster is created; allow enough Docker memory for it alongside existing clusters. The timer starts only after baseline checks succeed. `./k8s-sim.sh tasks`, `time` and `score` show this round's tasks, deadline and evidence checks. The original 22 drills remain available through `../k8s-sim.sh start` from this folder.

For each task, record the requested host/namespace/object. Use `./k8s-sim.sh kubectl ...`. Access control-plane files with `./k8s-sim.sh ssh`; reach the worker with `./k8s-sim.sh ssh --node cks-lab-m02`. Return to your Mac terminal between host tasks. Mac artifacts below use `.cks-state/jumpbox/exam`; copied component files are in `/opt/cks-lab/exam` **inside the lab node**. Files without `/exam` are shared staged input files.

**Fidelity:** tasks 2/3/5/7/9/11/12 use real workloads; task 4 provides replayed investigation evidence and real containment. Tasks 1/6/15/16 use copied configuration and require separate live verification. Tasks 8/10/13/14 require an external controller/tool or disposable Linux environment. The default round does not pretend these dependencies exist. Automatic scoring is capped at 47/100 (44 live + 3 replay); 53 points require manual/external evidence. No CKS pass prediction is produced.

## 1 — Component authentication — 7 points, manual

Host: control plane. In the copied `kubelet-config.yaml`, disable anonymous authentication, keep webhook authentication enabled and set authorization to Webhook. In the copied `etcd.yaml`, require client certificates and a trusted CA for client connections; preserve valid peer TLS and existing data paths. Kubelet flags cannot be applied to etcd. On a disposable kubeadm host, validate syntax, restart the relevant components and demonstrate rejection of unauthenticated requests while the node remains Ready.

## 2 — Restore a workload's certificate mount — 5 points, live

Namespace: `exam-tls`. Deployment `certificate-reader` cannot create a usable Pod because it references a missing Secret. Create `site-tls` using `.cks-state/jumpbox/tls.crt` and `tls.key`. Keep the Secret mount at `/tls`, read-only, and restore a healthy replica. Do not remove the mount or replace it with dummy content.

## 3 — Image user and Deployment constraints — 7 points, live/static

Namespace: `exam-build`. Change the **final image stage** in `exam/Dockerfile` to use the existing user `nobody`. Harden Deployment `build-app`: effective UID **65535**, read-only root filesystem, `privileged: false`, and `allowPrivilegeEscalation: false`. Keep it available. The scorer checks the Dockerfile statically and verifies the running Pod UID/root mount; independently build the image for full image verification. Do not assume a username always maps to a specific UID.

## 4 — Investigate an unknown workload — 7 points, replay/manual

Namespace: `exam-runtime`. Inspect `exam/runtime-events.jsonl`; identify the Pod opening `/dev/mem`, trace its owner and scale only its Deployment to zero. Keep the other two Deployments available. Save `exam/incident.json` with `namespace`, `pod` and `deployment`. The offending workload is chosen per attempt.

Write a WARNING Falco rule in `exam/falco_rules.local.yaml` for read/write opens of `/dev/mem`. Three points can be checked from replay investigation plus actual containment; four require a real Falco engine validating the rule and alert behavior. No `/dev/mem` access is performed by setup.

## 5 — Container immutability — 6 points, live

Namespace: `exam-immutable`. Harden `immutable-app`: effective UID **30000**, read-only root filesystem, no privilege escalation and no privileged container. Keep the Deployment available. Confirm the running UID and root mount rather than merely editing a template.

## 6 — Audit coverage and retention — 7 points, manual

Host: control plane. Correct `/opt/cks-lab/audit/audit-policy.yaml` to record request metadata for all API operations without recording Secret bodies. Configure the copied API server manifest with policy/log mounts, `/var/log/k8s/audit.log`, **2** backup files, **7** days maximum age and **10 MiB** maximum file size. On a disposable live control plane generate requests and verify log delivery/rotation. Adding flags to the copied manifest is rehearsal only.

## 7 — Namespace-based ingress — 7 points, live

Namespace: `exam-backend`. Create `default-deny-ingress`, selecting all Pods and denying inbound connections by default. Add a narrowly scoped allow rule so only Pods from `exam-allowed` may access `app=api` on TCP/8080. Keep egress unrestricted for this exercise. Preserve all workloads and the `probe` Pods.

The baseline proves all three probe sources can reach the server before your change. Scoring requires a Ready backend and clients, a successful request from `exam-allowed`, and blocked requests from `exam-denied` and another Pod in `exam-backend`. A failed exec command does not count as blocked traffic.

## 8 — HTTPS Ingress — 6 points, external

Namespace: `exam-ingress`. A working `web` Service exposes the backend on port 80. With a real installed controller, create an Ingress for `exam.cks.local`, terminate TLS using a Secret in this namespace, route `/` to `web:80` and redirect HTTP to HTTPS. Verify the redirect and trusted HTTPS response with SNI/Host set correctly.

The candidate report uses `nginx.ingress.kubernetes.io/ssl-redirect`, which is controller-specific. The community ingress-nginx project retired in March 2026; it is not automatically installed here. Use the controller actually provided in your practice/exam environment and consult its documentation.

## 9 — Explicit API token projection — 6 points, live

Namespace: `exam-tokens`. Disable token automount on `app-sa`. Create Ready Pod `token-client` with that ServiceAccount and pod-level automount also disabled. Mount an explicit projected token read-only at `/var/run/secrets/tokens`, token filename `token`, audience `cks-lab`, lifetime **3600** seconds. This audience is an exercise value, not an assumption about API server audiences.

## 10 — Worker patch upgrade — 7 points, external

Host: a separate disposable kubeadm worker, initially one patch behind its control plane. Determine exact available package versions, drain appropriately, upgrade kubeadm, run `kubeadm upgrade node`, upgrade node packages, restore package holds, restart kubelet and uncordon. Verify the target version, schedulability, node health and workload recovery.

`cks-lab-m02` provides a second SSH target for navigation/drain practice, but Minikube's managed binaries do not reproduce an apt-managed kubeadm worker. Do not count creating two current-version nodes as a completed upgrade. Avoid copying unconditional `--force` or data-deletion flags from a report without checking the workload.

## 11 — SBOM-driven container identification — 7 points, live/artifact

Namespace: `exam-supply`. Deployment `inventory` contains `amber` and `cobalt`; the image assignment varies. Generate a real SPDX document for **each** image, using an installed trusted BOM tool. Save `exam/amber.spdx` and `exam/cobalt.spdx` on your Mac. Inspect which image includes package **libcrypto3**. Package presence alone is not a claim of a specific vulnerability.

Save `exam/findings.json` with exactly `container`, `image` and `package`. Remove only the identified container from the Deployment template and keep the other container available. Do not remove the entire workload. Reports may use SPDX 2.x JSON or tag/value format and must contain package data.

## 12 — Repair a Restricted Deployment — 6 points, live

Namespace: `exam-restricted` already enforces Restricted Pod Security. Diagnose why `locked-app` cannot create compliant Pods. Fix the Deployment, including all relevant security context constraints, and restore a healthy replica. Keep namespace enforcement active; weakening/removing the namespace label is not a solution.

## 13 — Docker privilege removal — 5 points, external

On a disposable Docker host, remove a specified unauthorized user from the Docker group and restore `/var/run/docker.sock` ownership to `root:docker` with appropriate permissions. Verify effective group/session access. The containerd-based Kubernetes nodes do not serve as a pretend Docker daemon; no real Mac user/socket ownership is changed by this round.

## 14 — Cilium mutual authentication with host exception — 6 points, external

In a dedicated Cilium+SPIRE environment, target `app=invoices` in `exam-mesh`. Allow application traffic from `exam-allowed` on TCP/8080 only with mutual authentication. Permit local host access through a distinct rule without that requirement. Verify both application identity enforcement and the host exception. This replaces treating a DNS-only policy as an equivalent exercise. If traffic encryption is required, configure and verify WireGuard/IPsec separately.

## 15 — Fail-closed image admission — 6 points, manual

Host: control plane. Use the staged admission configuration and kubeconfig; preserve existing admission plugins, enable ImagePolicyWebhook and configure required file flags/mounts in the copied API server manifest. Set `defaultAllow: false`. On an external disposable control plane, use a reachable authenticated test backend and prove allowed, denied and unavailable-backend cases. The staged `.invalid` backend URL is not a working webhook.

## 16 — API server identity and authorization — 5 points, manual

Host: control plane. In the copied API server manifest, disable anonymous authentication, require `Node,RBAC` authorization and enable NodeRestriction without dropping other required plugins. Verify the real configuration and API health in a disposable Linux control plane. Preserve recovery copies outside the watched static-manifest directory.

After the round, record the unresolved tasks and the evidence that failed. Open `EXAM-SOLUTIONS.md` only after your attempt. Retain the original drill bank for AppArmor/seccomp, encryption, signatures, scanning and RBAC topics absent from this particular candidate's report.
