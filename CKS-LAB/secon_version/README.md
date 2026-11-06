# Second CKS mock exam

This folder contains the 16-task, two-hour mock, its solutions and supporting files.

- [EXAM.md](EXAM.md): 16 exam-style questions with host information, context and task requirements.
- [EXAM-NOTES.md](EXAM-NOTES.md): lab prerequisites, file locations, scoring limits and verification notes.
- [EXAM-SOLUTIONS.md](EXAM-SOLUTIONS.md): one step-by-step solution per task, with commands, Vim edits and expected results.
- [EXAM-SOURCES.md](EXAM-SOURCES.md): sources and corrections.
- `exam_mode.py`: scenario setup and scoring.
- `examples/`: supporting policy example.
- `tests/`: mock-specific regression tests.

## Update between Macs

Use the repository's normal commit/push/pull workflow. Include changes in the parent `CKS-LAB` runtime as well as this folder; both are required. Run `git pull --ff-only` on the other Mac after pushing the committed changes. No separate installer is needed. See [the shared update instructions](../README.md#update-between-macs-using-git).

Git leaves each Mac's ignored `.cks-state` directory intact. Run `./k8s-sim.sh score --task 1` to check an existing answer after pulling a grader update. Do not run `start` merely to load an update: it archives the current attempt and creates a new one.

## Start the mock

1. Open **Docker Desktop** and wait for its engine to be running. The simulator creates and configures its own two-node Minikube cluster; you do not need to start a Minikube container manually. Prerequisites are Minikube, a compatible kubectl client, Python 3 and OpenSSL, as described in the parent README.
2. Open a terminal and run:

```bash
cd /Users/gabo/Documents/Proyectos/kubernetes-questions/CKS-LAB/secon_version
./k8s-sim.sh start
```

3. Each `start` automatically saves the previous attempt under `../.cks-state/archives/`, removes the previous owned lab cluster and creates a fresh exam. Local answers, timing information, Kubernetes resource snapshots and available node files are backed up first. Use `time`, `score` or `kubectl` to continue working on your current attempt.
4. Wait for **“Session started: 120 minutes”**. Setup may download images on the first run. The two-hour countdown starts only after setup succeeds.
5. Display the questions:

```bash
./k8s-sim.sh tasks
```

Read [EXAM.md](EXAM.md) during your attempt and open [EXAM-SOLUTIONS.md](EXAM-SOLUTIONS.md) afterwards. The launcher also accepts the former `start --exam` spelling.

## Work on the tasks

Use the simulator wrapper for Kubernetes commands so they target the lab regardless of your current context:

```bash
./k8s-sim.sh kubectl get pods -A
```

For an interactive control-plane session:

```bash
./k8s-sim.sh ssh
```

For an interactive worker session:

```bash
./k8s-sim.sh ssh --node cks-lab-m02
```

Inside either SSH node, use `kubectl` directly:

```bash
kubectl get nodes
kubectl get pods -A
kubectl edit deployment build-app -n exam-build
```

Setup exposes the bundled, cluster-matching client and a private kubeconfig on both nodes, for the SSH user and `sudo -i`. It uses the lab API address reachable between nodes and keeps TLS verification enabled. Existing shell sessions can run `source /etc/profile.d/cks-lab-kubectl.sh` or reconnect to pick up the connection setting.

Run `exit` inside the node session to return to your Mac terminal before using the simulator commands again. Enter one node session at a time.

## Plain kubectl on your Mac

After successful setup, startup selects `cks-lab` if your previous context was empty or already `cks-lab`. This restores the selection after a fresh attempt recreates the cluster. An unrelated selected cluster is preserved; the simulator wrapper always targets the lab.

To select the existing lab for plain Mac commands without restarting:

```bash
kubectl config use-context cks-lab
kubectl get nodes
```

If plain kubectl tries `http://localhost:8080`, it is not using the lab endpoint. Select the lab as above or use `./k8s-sim.sh kubectl get nodes`. This context selection does not reset the exam or timer.

## Use Vim

The simulator uses **Vim** as its preferred editor. `kubectl edit` through the wrapper opens Vim on your Mac:

```bash
./k8s-sim.sh kubectl edit deployment build-app -n exam-build
```

Inside either node, edit files directly with Vim:

```bash
sudo vim /opt/cks-lab/exam/kube-apiserver.yaml
```

Setup installs Vim on both owned exam nodes and sets `EDITOR`, `VISUAL` and `KUBE_EDITOR` to `vim`. Installation finishes before the exam timer begins. Reconnect an existing SSH session to pick up the node defaults, or run `source /etc/profile.d/cks-lab-editor.sh` there.

For plain `kubectl edit` outside the wrapper, set these in your current terminal:

```bash
export EDITOR=vim VISUAL=vim KUBE_EDITOR=vim
```

## Timer and scoring

Check the remaining time:

```bash
./k8s-sim.sh time
```

Grade your work:

```bash
./k8s-sim.sh score
```

Check one answer at a time, for example question 1:

```bash
./k8s-sim.sh score --task 1
```

Scoring rereads the saved node files each time. Tasks 1, 6, 15 and 16 show `PASS CONFIG`/`FAIL CONFIG` with individual PASS/FAIL requirements; invalid YAML, duplicate keys/flags and unreadable evidence show `ERROR`. All required checks must pass to earn that task's points. These checks do not activate copied configuration or test live component enforcement. A YAML parser is bundled, so no package installation is needed. Updating the grader preserves your current answers and timer; no new exam is required.

The timer displays `EXPIRED` when time runs out. Expiry is advisory: your work remains available and you can still score it.

## Finish and clean up

When you want to remove the lab cluster, run:

```bash
./k8s-sim.sh cleanup
```

Manual cleanup is optional. For another attempt, simply run `./k8s-sim.sh start` again: it archives the old attempt and performs cleanup automatically. Manual `cleanup` removes only the owned `cks-lab` profile and retains your local answer files.

Backups are kept in the parent `.cks-state/archives/<timestamp>_<unique-id>/` directory. Each contains the previous `jumpbox/` and session metadata. When a previous cluster is available, `cluster-resources.json` saves its workload/configuration objects and `node-files.tar.gz` saves its `/opt/cks-lab` files. Archives are private to your user because they include lab Secrets and certificate keys. The new archive path is printed during startup. Archives are never removed automatically.

Startup stops before deleting the old cluster if it cannot verify ownership or create the backup. If local answers change after the snapshot, it retains those files and stops before starting the new exam. If the API is unavailable, restore lab access first. If deletion fails, the current local answers and timer remain in place and the backup is retained.

## Shared runtime and file locations

The mock shares the parent simulator's guarded runtime, `cks-lab` profile and `.cks-state` directory. Run one mock at a time. The original simulator remains in the parent directory; its `./k8s-sim.sh start --exam` command still works. This folder must stay inside `CKS-LAB` so the shared scripts remain available.

Run the task and solution commands from `secon_version`. **For Mac commands such as `vim`, use `../.cks-state/jumpbox/exam/`; shared certificates are in `../.cks-state/jumpbox/`.** The launcher resolves file arguments passed to its kubectl wrapper from the parent `CKS-LAB` directory, so wrapper arguments such as `--cert=.cks-state/jumpbox/tls.crt` omit `../`. Commands in the solution guide use the appropriate path for each case. Node paths such as `/opt/cks-lab/exam` are inside the node and stay the same.

The automatic score ceiling is 72/100: 47 workload/replay points plus 25 configuration-copy points. The remaining 28 require manual/external evidence. Scenario revision 2 starts the assigned local controls in explicitly incorrect states and audits those faults before the timer begins. See [the starting-state contract](EXAM-NOTES.md#starting-state-contract). Updating the files preserves your current attempt; run `start` when ready to archive it and begin the revised scenarios.

Run the mock-specific offline tests from this folder:

```bash
python3 -B -m unittest discover -s tests -v
```

## Backup troubleshooting

If a backup fails, startup keeps the existing lab. The error gives the archive directory; inspect `node-backup.log` there for SSH diagnostics. After correcting the problem, run `./k8s-sim.sh start` again. The backup transfer handles Minikube's terminal-based SSH connection automatically.

## Missing local session record

If a simulator node still exists after the local ownership file is lost, `start` can recover automatically. It verifies the node's `cks-lab-fixtures-v1` marker, independently reads the cluster identity using the node's admin kubeconfig and matches it against the host connection. It then restores `../.cks-state/cluster-uid`, archives the previous attempt and starts a fresh exam normally.

Recovery does not invent a timer or resume lost session metadata. Profiles without the simulator marker, unreachable APIs and identity mismatches are retained. Pull the complete repository update on the affected Mac before retrying `./k8s-sim.sh start`.
