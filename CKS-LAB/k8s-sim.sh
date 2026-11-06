#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
start_exam() {
    need minikube; need kubectl; need python3; need openssl; need vim
    local profiles version mode nodes profile_status archive_dir previous_context
    [ "$#" -le 1 ] || die "Use start or start --exam."
    mode=drills; nodes=1
    case "${1:-}" in
        --exam) mode=exam; nodes=2 ;;
        "") ;;
        *) die "Use start or start --exam." ;;
    esac
    version=${CKS_KUBERNETES_VERSION:-v1.35.0}
    [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Use a version such as v1.35.0."
    lock_lab
    profiles=$(minikube profile list -o json 2>/dev/null) || true
    profile_status=$(printf '%s' "$profiles" | python3 -c '
import json, sys
try:
    p = json.load(sys.stdin)
    if not isinstance(p, dict) or not all(k in p and isinstance(p[k], list) for k in ("valid", "invalid")):
        raise ValueError("invalid profile list")
    entries = p["valid"] + p["invalid"]
    if not all(isinstance(e, dict) and isinstance(e.get("Name"), str) for e in entries):
        raise ValueError("invalid profile entry")
    print("present" if any(e["Name"] == "cks-lab" for e in entries) else "absent")
except (ValueError, TypeError, AttributeError):
    sys.exit("Cannot inspect Minikube profiles; refusing to start.")
')
    if [ "$profile_status" = present ]; then
        if [ ! -s "$STATE_DIR/cluster-uid" ]; then
            recover_lab_identity
        fi
        require_lab
        previous_context=$(kubectl config current-context 2>/dev/null || true)
        archive_dir=$(python3 "$LAB_DIR/attempt_archive.py" prepare --node)
        echo "Previous attempt saved to: $archive_dir"
        delete_owned_lab
    else
        previous_context=$(kubectl config current-context 2>/dev/null || true)
        archive_dir=$(python3 "$LAB_DIR/attempt_archive.py" prepare)
        if [ -n "$archive_dir" ]; then
            echo "Previous attempt saved to: $archive_dir"
        fi
    fi
    python3 "$LAB_DIR/attempt_archive.py" finish "$archive_dir"
    clear_session_state
    printf "%s\n" "$mode" > "$STATE_DIR/mode"
    echo "Creating dedicated profile $PROFILE ($version, Calico)."
    if [ "$mode" = exam ]; then
        minikube -p "$PROFILE" start --kubernetes-version="$version" --cni=calico --driver=docker --container-runtime=containerd --keep-context --nodes="$nodes"
    else
        minikube -p "$PROFILE" start --kubernetes-version="$version" --cni=calico --driver=docker --container-runtime=containerd --keep-context
    fi
    local created_uid
    created_uid=$(k get ns kube-system -o jsonpath='{.metadata.uid}' --request-timeout=15s) || die "Could not read new cluster ownership; no ownership record was written."
    save_cluster_uid "$created_uid"
    k wait --for=condition=Ready nodes --all --timeout=180s
    bash "$LAB_DIR/exam-setup.sh"
    # Recreating Minikube can remove its active context. Keep unrelated choices,
    # but make plain kubectl work on a new Mac or a continued lab workflow.
    case "$previous_context" in
        ""|"$PROFILE") kubectl config use-context "$PROFILE" >/dev/null ;;
    esac
    python3 - "$STATE_DIR/deadline" <<'PY'
import pathlib, sys, time
pathlib.Path(sys.argv[1]).write_text(str(int(time.time()) + 7200))
PY
    echo "Session started: 120 minutes. Jumpbox files: $JUMPBOX_DIR"
    echo "Commands: ./k8s-sim.sh kubectl ... | ssh | score | time | cleanup"
}
case "${1:-}" in
    start) shift; start_exam "$@" ;;
    score)
        shift
        require_lab; need python3
        if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
            python3 "$LAB_DIR/secon_version/exam_mode.py" score "$@"
        else
            [ "$#" -eq 0 ] || die "Task selection is available in the second mock: score --task NUMBER."
            python3 "$LAB_DIR/score.py"
        fi
        ;;
    tasks)
        if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
            cat "$LAB_DIR/secon_version/EXAM.md"
        else
            cat "$LAB_DIR/TASKS.md"
        fi
        ;;
    time)
        need python3
        python3 - "$STATE_DIR/deadline" <<'PY'
import pathlib, sys, time
try:
    remaining = max(0, int(pathlib.Path(sys.argv[1]).read_text()) - int(time.time()))
    print(f"{remaining // 3600:02}:{remaining // 60 % 60:02}:{remaining % 60:02}" if remaining else "EXPIRED")
except (OSError, ValueError):
    sys.exit("No active timer.")
PY
        ;;
    cleanup) bash "$LAB_DIR/exam-cleanup.sh" ;;
    kubectl) require_lab; shift; k "$@" ;;
    ssh) require_lab; shift; node "$@" ;;
    *) echo "Usage: $0 {start [--exam]|tasks|score|time|cleanup|kubectl ...|ssh [--node NAME] [command]}"; exit 1 ;;
esac
