# Lab scope and grading

Read before starting the mock. The question sheet uses a host information box, a short context and a task specification for each exercise. These are original training questions, not reproduced exam questions or a promise of the exact current ExamUI wording. The [official CKS instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks) describe designated SSH hosts, a host information box at the start of each task and returning to the base host between tasks. This lab adapts that workflow to a Mac terminal and Minikube.

The [candidate report](https://www.reddit.com/r/KubernetesCerts/comments/1rzoh2s/passed_cks_heres_what_actually_came_up/) inspired the topic sequence. The 16 tasks, workloads and weights are local training choices. See [sources](EXAM-SOURCES.md) for technical corrections and broader preparation topics. Scenario revision 2, introduced on 5 November 2026, deliberately initializes the required local repairs as unfinished and verifies the starting state before the timer begins. Weights and the automatic scoring ceiling are unchanged.

## Environment and paths

The launcher in `secon_version` uses the parent `CKS-LAB` runtime and creates a two-node Docker/Calico cluster. Each `start` archives the previous attempt and replaces the verified owned lab. Use `time`, `score`, `ssh` and `kubectl` to continue an attempt.

| Location | Meaning |
| --- | --- |
| `cks-lab` | Control-plane SSH target: `./k8s-sim.sh ssh` |
| `cks-lab-m02` | Worker SSH target: `./k8s-sim.sh ssh --node cks-lab-m02` |
| `/opt/cks-lab/exam/` | Copied component files inside the control-plane node |
| `../.cks-state/jumpbox/exam/` | Exam files on your Mac, relative to `secon_version` |
| `../.cks-state/jumpbox/` | Shared certificate and key on your Mac, relative to `secon_version` |

The task and solution sheets use explicit Mac paths for local file operations. The launcher resolves file arguments passed to its kubectl wrapper from the parent `CKS-LAB` directory. For example, `vim ../.cks-state/jumpbox/tls.crt` from this folder and the wrapper's `--cert=.cks-state/jumpbox/tls.crt` argument refer to the same file. The solution guide labels Mac, SSH and external-lab commands separately.

Copied configuration is not activated. Never overwrite active Minikube API server, kubelet or etcd configuration with the supplied copies. External environments, controllers and tools named as prerequisites are not created automatically.

## Starting-state contract

A fresh revision-2 exam must begin with the following faults. Startup reads back the uploaded copies and the actual workload objects; it stops before the timer if an assigned field is already repaired or the fixtures do not match.

| Tasks | Deliberate starting faults |
| --- | --- |
| 1 | Anonymous kubelet access enabled, webhook authentication disabled, AlwaysAllow authorization, etcd client certificates not required and an incorrect client CA path. All five changes are yours to make. |
| 3, 5 | Explicit root UID, writable root filesystem, privileged execution and privilege escalation enabled. |
| 6 | Incomplete audit coverage, Secret bodies recorded, incorrect policy/log paths and all three retention limits wrong; required mounts absent. |
| 9 | Existing Pod and ServiceAccount both enable automount; explicit projection has the wrong filename, audience, lifetime, mount path and read-only setting. Recreate the Pod with the correct complete specification. |
| 12 | Explicit root identity, non-root disabled, Unconfined seccomp, privileged execution, privilege escalation, no ALL capability drop and an added SYS_ADMIN capability. Restricted admission blocks the Pods. |
| 15, 16 | ImagePolicyWebhook and NodeRestriction explicitly disabled and absent from the enabled list; wrong admission-file path, fail-open webhook, missing mount, anonymous API access and AlwaysAllow authorization in the copy. |
| 2, 4, 7, 11 | Required Secret/policies/reports/findings are absent; the incident is not contained and both inventory containers remain present. Healthy applications, certificate inputs and test clients are prerequisites for these tasks. |

The setup records the successful local starting checks in the existing private `exam-expected.json` session metadata. It does not overwrite an in-progress attempt when you update the scripts. Use `start` when you are ready for a new attempt. Old attempts retain their original starting state.

External tasks 8, 10, 13 and 14 still require their documented controller/host/cluster prerequisites. This revision does not pretend those systems are supplied. Their runtime verification remains manual/external. Component-copy exercises now receive automatic configuration checks, with live enforcement still outside this lab.

## What can be graded locally

The automatic ceiling is **72/100**: 44 points from tasks 2, 3, 5, 7, 9, 11 and 12, plus 3 replay/containment points from task 4 and 25 configuration-copy points from tasks 1, 6, 15 and 16. The remaining **28 points** require manual/external evidence. Scores are not normalized to 100 and do not predict an exam pass.

| Tasks | Local evidence | Additional verification |
| --- | --- | --- |
| 1, 6, 15, 16 | Parsed YAML, required settings, flags, mounts and preserved component prerequisites; automatic CONFIG checks | Apply appropriate real configuration on a separate disposable Linux control plane, verify syntax, component/API health and the intended behavior. |
| 2 | Original certificate, valid TLS Secret, preserved mount and healthy Deployment | Inspect events and mounted material as needed. |
| 3, 5 | Security configuration, available replicas, effective UID and actual read-only root mount; task 3 also checks final-stage Dockerfile user | Build/run task 3's image separately to validate its image user. Editing the Dockerfile does not rebuild the Deployment image. |
| 4 | Replayed events, identified workload and actual containment: up to 3 points | A real Falco engine must validate the rule and alert behavior for the remaining 4 points. Setup never opens `/dev/mem`. |
| 7 | Actual Calico-backed traffic from allowed, denied and same-namespace clients | Keep backend and clients healthy. Failed command execution is not proof of denied traffic. Policies are additive. |
| 8 | Backend Service is provided | Install a real controller; verify redirect, routing, TLS and certificate identity. |
| 9 | Explicit projection, requested lifetime/audience, both automount settings, read-only mount and Ready Pod | Requested lifetime may differ from actual issued lifetime. The audience is an exercise value, not a statement about API server accepted audiences. |
| 10 | Worker SSH target for navigation/drain practice | Use a real package-managed kubeadm worker for an actual patch upgrade. Minikube's managed binaries do not reproduce this workflow. |
| 11 | Both SPDX package reports, exact finding, removal of the correct container and healthy survivor | Install a trusted SBOM tool separately and generate reports from the actual image references. Package presence alone is not a vulnerability claim. |
| 12 | Restricted namespace label, compliant security settings and healthy Pods | Diagnose admission failures without weakening namespace enforcement. |
| 13 | No Docker daemon/socket exercise is provisioned on the containerd nodes | Use a separate disposable Linux Docker host with a designated user; verify effective sessions and socket access. |
| 14 | No Cilium/SPIRE environment is provisioned | Use a dedicated Cilium/SPIRE lab; verify application identity and local host access. Mutual authentication does not itself encrypt payloads. |

## Checking saved answers

`./k8s-sim.sh score` checks all supported tasks. `./k8s-sim.sh score --task 1` checks only question 1; substitute any task number from 1 to 16. Each command rereads the current files and objects without resetting the session or changing a component.

For component copies, `PASS CONFIG` means all task requirements and preserved component prerequisites passed static checks. `FAIL CONFIG` lists the requirements still unmet. Every requirement must pass before configuration points are awarded; there is no credit merely for inherited correct defaults. `ERROR` means the evidence could not be read or parsed, and receives no credit. Malformed YAML, duplicate keys, conflicting command flags, wrong CA paths, missing mounts and explicitly disabled required plugins do not pass.

The grader uses a bundled pinned PyYAML SafeLoader with duplicate-key rejection, so flow-style YAML and normal formatting variations are supported without installing anything on the Mac. Validation covers the specified settings and component prerequisites; it is not a full Kubernetes schema check, nor proof that an edited copy was activated. Test real authentication, log rotation and webhook behavior separately on disposable infrastructure. Tasks 8, 10, 13 and 14 remain manual/external, as do the four Falco-engine points in task 4.

## Technical notes for review

- Kubelet webhook/authorization fields do not configure etcd; etcd uses certificate-based transport controls. Preserve peer TLS and authenticated client access.
- The image username `nobody` and task 3's requested numeric runtime UID are separate requirements; do not assume the name maps to that UID.
- A basic Metadata audit policy avoids capturing Secret bodies. For live verification, generate requests and inspect actual delivery and rotation; flags in a copy are rehearsal only.
- Ingress redirect settings depend on the installed controller. The retired community ingress-nginx controller is not installed automatically. See the source sheet for the retirement reference.
- For worker upgrades, inspect available package revisions and workload constraints before draining. Avoid unconditional force or data-deletion options.
- The staged image webhook's `.invalid` backend is intentionally unreachable. Use a reachable authenticated backend on a disposable control plane to test allowed, denied and unavailable-backend behavior.
- Cilium's local `host` and `remote-node` identities are distinct. Check other policies for additive bypasses; configure WireGuard/IPsec separately if an exercise requires traffic encryption.
- Keep recovery copies outside watched static-manifest directories when practicing live component changes on a disposable Linux cluster.

After the attempt, review [solutions](EXAM-SOLUTIONS.md), record failed evidence and revisit the original drill bank for AppArmor/seccomp, encryption, signatures, scanning and RBAC coverage beyond this particular report.
