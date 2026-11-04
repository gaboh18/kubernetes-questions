# Second CKS mock exam

This folder contains the 16-task, two-hour mock, its solutions and supporting files.

- [EXAM.md](EXAM.md): tasks, points, requirements and fidelity limits.
- [EXAM-SOLUTIONS.md](EXAM-SOLUTIONS.md): solutions, commands and evidence checklists.
- [EXAM-SOURCES.md](EXAM-SOURCES.md): sources and corrections.
- `exam_mode.py`: scenario setup and scoring.
- `examples/`: supporting policy example.
- `tests/`: mock-specific regression tests.

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

Run `exit` inside the node session to return to your Mac terminal before using the simulator commands again. Enter one node session at a time.

## Timer and scoring

Check the remaining time:

```bash
./k8s-sim.sh time
```

Grade your work:

```bash
./k8s-sim.sh score
```

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

**Artifact paths in the task/solution sheets are relative to the parent `CKS-LAB` directory.** From here, edit artifacts under `../.cks-state/jumpbox/exam/`; shared certificates are in `../.cks-state/jumpbox/`. The launcher resolves command file arguments from the parent, so the documented `--cert=.cks-state/...` commands still work. Node paths such as `/opt/cks-lab/exam` are unchanged.

The automatic score ceiling remains 47/100; 53 points require manual/external evidence. This folder move does not change the scenarios or scoring.

Run the mock-specific offline tests from this folder:

```bash
python3 -B -m unittest discover -s tests -v
```
