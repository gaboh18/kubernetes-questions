# CKS practice lab

This is a lightweight Kubernetes security practice lab, not a complete CKS exam simulator. The original question numbers are retained, with a new least-privilege RBAC task (Q22). Read [TASKS.md](TASKS.md) before opening [SOLUTIONS.md](SOLUTIONS.md).

Reviewed on **2026-10-31**. The [Linux Foundation technical instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks) currently specify Kubernetes **v1.35**, a two-hour exam, and tasks performed on designated SSH hosts. Recheck this source before your exam; the default lab version is configurable.

## Candidate-report mock

The second 16-task mock is in [secon_version/](secon_version/README.md), including its instructions, solutions, sources, examples and tests. Start it from this directory with:

```bash
./secon_version/k8s-sim.sh start
./secon_version/k8s-sim.sh tasks
./secon_version/k8s-sim.sh score
```

Read [EXAM.md](secon_version/EXAM.md) for tasks and fidelity limits, [EXAM-SOLUTIONS.md](secon_version/EXAM-SOLUTIONS.md) after your attempt, and [EXAM-SOURCES.md](secon_version/EXAM-SOURCES.md) for corrections to the report. This mode creates **two** lab nodes, real broken workloads, namespace traffic probes, randomized SBOM/incident targets, and a separate weighted rubric. Scenario revision 2 deliberately breaks every assigned local hardening field and audits the starting faults before the timer begins; see [the starting-state contract](secon_version/EXAM-NOTES.md#starting-state-contract). Use `./k8s-sim.sh ssh --node cks-lab-m02` to practise reaching the worker. It requires enough Docker resources for both nodes alongside any existing clusters.

The automatic ceiling in exam mode is **72/100**: 44 points for live workload checks, 3 for incident replay plus containment and 25 for configuration-copy checks. The other 28 require external/manual evidence; no perfect normalized score hides missing infrastructure. The original 22-task practice bank and its 55-point configuration score remain available through plain `start`. Each `start` archives the previous attempt and replaces the owned lab profile automatically. Other profiles are preserved.

## Update between Macs using Git

The whole simulator is versioned here: parent launchers and archive/editor/client helpers, plus `secon_version` scenarios, grader and bundled parser. Commit shared-runtime changes together with any mock changes, then push from the source Mac. Pushing alone does not include uncommitted or untracked files.

On the other Mac, run `git pull --ff-only` from the repository and use the updated scripts normally. No downloaded installer is required. Existing `.cks-state` answers, credentials, archives and timer remain local and are ignored by Git. A grader update takes effect on the next `score` command without restarting the exam; scenario setup changes apply to the next fresh `start`.

## Start and work

Prerequisites: a running Docker daemon, an installed compatible kubectl client, Minikube with support for your selected Kubernetes version, Python 3, Vim, and OpenSSL with `req -addext` support. The first start downloads cluster/CNI/workload images and needs internet access. No host packages or scanning tools are installed automatically. Setup ensures Vim is installed inside the owned lab nodes and configures it as their default editor before the timer starts. Lab wrapper commands also set EDITOR, VISUAL and KUBE_EDITOR to vim.

```bash
./k8s-sim.sh start
./k8s-sim.sh kubectl get pods -A
./k8s-sim.sh ssh
./k8s-sim.sh time
./k8s-sim.sh score
```

The commands above use the original drill mode. Run these from this directory, or invoke the script by its full path. Use the `kubectl` wrapper for all exercise commands: it always targets **cks-lab**, regardless of your current context. Use `./k8s-sim.sh ssh 'command'` for node commands. An interactive SSH session already runs inside the lab node. Inside either node, use kubectl directly; setup provides the bundled client and a private kubeconfig for the SSH user and root.

For a different supported version, use `CKS_KUBERNETES_VERSION=v1.35.1 ./k8s-sim.sh start`. The default is v1.35.0. Minikube uses a dedicated Docker profile, containerd, and Calico; an unrelated selected context is retained. If no context was selected, or the previous selection was `cks-lab`, successful setup selects `cks-lab` so plain `kubectl` works after each fresh attempt. Successful startup waits for nodes and baseline workloads, then starts the two-hour wall-clock timer. Expiry is advisory: it does not destroy work or stop scoring.

Start verifies ownership of an existing `cks-lab` profile, saves its local/session/node work and Kubernetes resource snapshot, then removes it before creating a fresh attempt. Scripts record the cluster's `kube-system` namespace UID and require a match before setup, scoring, wrapper commands, or cleanup. An unowned profile is never replaced. These checks prevent accidental targeting; they are not protection against a malicious user who can edit local state.

## Files and advanced exercises

| Location | Purpose |
| --- | --- |
| `.cks-state/jumpbox/` on your Mac | Dockerfile, TLS pair, Trivy output |
| `/opt/cks-lab/` **inside cks-lab** | Copied API server/kubelet files, admission/audit/encryption/AppArmor/Falco fixtures, checksum exercise, SBOM output |
| `.cks-state/deadline` | Timestamp-based timer; no background timer process |

Setup does not edit active API server/kubelet files, change real Docker socket ownership, or install placeholder CRDs. Q1/Q9/Q13/Q17 are **file-only simulations**. Never copy the staged manifest over the active manifest: it contains deliberately incomplete configurations. Q2 and Q20 require a separate disposable Linux host. Q4/Q5/Q6/Q8/Q19 need real tooling/controllers/kernel support and manual verification. A CRD alone does not provide a CNI or service mesh. Q5 is a DNS policy task; pod-to-pod encryption needs separate practice.

The existing `cilium.yaml`, `istio.yaml`, and `np.yaml` are personal answer files and are not applied automatically. In particular, `cilium.yaml` selects only `org=alliance` endpoints, while Q5 requires all application endpoints.

## Scoring and validation

In the original drill mode, `score` checks **11 of 22 tasks**, each worth five practice points, for a maximum of **55**. Eleven advanced tasks are listed as `MANUAL`, receive no automatic credit, and remain visible in the coverage count. There is no automatic upgrade credit and no CKS pass/fail prediction.

Checks inspect configuration and, where applicable, workload readiness: empty report files, missing pods, wrong token mounts, non-TLS secrets, mismatched certificate keys, incomplete rollouts, or connection failures do not earn points. Failed evidence reads are `ERROR` and cause a nonzero exit code; ordinary unsolved checks are `FAIL`. RBAC checks include selected effective allow/deny probes. A structurally valid report can still be fabricated; the score does not prove report provenance, network enforcement, runtime behavior, or complete least privilege. Default-deny checks conservatively reject any additional policy with allow rules in `backend`.

```bash
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s secon_version/tests -v
bash -n k8s-sim.sh exam-setup.sh exam-cleanup.sh lab-common.sh
```

Tests are offline and use a fake Minikube executable. They cover isolation/refusal paths, lifecycle failures, scoring false positives, readiness, reports, TLS key matching, and RBAC. They do not replace a full run on a new cluster or enforcement tests.

## Cleanup and another attempt

```bash
./k8s-sim.sh cleanup
```

For another attempt, run `start` again. It automatically verifies and saves local answers, session metadata, Kubernetes resource snapshots and available node files in `.cks-state/archives/<timestamp>_<unique-id>/`, removes the previous owned profile, then creates the new exam. Manual `cleanup` remains available when you want to remove the lab immediately; it retains local answers for the next automatic archive. Backups are retained indefinitely, and startup prints their location. The state directory gets a local ignore file so keys and generated answers are not accidentally committed.

If the initial backup or ownership checks fail, the previous lab is retained. If answers change after the backup, those local files are retained and the new start stops. Archives include lab Secrets and are stored in private directories. If deletion fails, original local answers and timer metadata are retained. A stopped/unreachable API must be restored before ownership can be verified; startup does not bypass that guard.

If startup fails before it can record a cluster UID, inspect `minikube profile list` and the failure message. The scripts deliberately refuse to adopt that profile. After verifying that `cks-lab` is the newly created disposable profile, remove that profile manually with `minikube -p cks-lab delete`. If cleanup cannot reach the API to verify ownership, restore access or inspect the profile manually; no automatic bypass is provided. A leftover `.cks-state/lock` after a forced interruption must be inspected and removed only when no lab operation is active.

Existing `minikube` profiles, old `/opt/cks-lab` files on the Mac, `.timer_pid`, and `.remaining_time` are not migrated or removed. The new scripts do not use the legacy timer process or files.

## Preparation beyond this lab

Use a disposable Linux kubeadm cluster for actual upgrades, component restarts, encryption migration, auditing, and kernel enforcement. Extend the workload lab with registry/signature admission, static workload analysis, isolation/sandboxing, metadata protection, and investigation of real audit/runtime events. Compare readiness against the [current curriculum](https://github.com/cncf/curriculum) and [exam resources](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed), then complete an unseen timed mock. Repeating these known answers is not sufficient evidence of exam readiness.
