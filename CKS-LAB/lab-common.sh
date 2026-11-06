#!/bin/bash
# Fixed profile and paths prevent accidental use of another cluster.
set -euo pipefail
LAB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROFILE=cks-lab
STATE_DIR="$LAB_DIR/.cks-state"
JUMPBOX_DIR="$STATE_DIR/jumpbox"
# Vim is the preferred editor for lab commands, including kubectl edit.
export EDITOR=vim VISUAL=vim KUBE_EDITOR=vim
die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Install $1 before using the simulator."; }
k() {
    local arg
    for arg in "$@"; do
        [ "$arg" != "--" ] || break
        case "$arg" in
            --context|--context=*|--cluster|--cluster=*|--server|--server=*|--kubeconfig|--kubeconfig=*|--user|--user=*|-s|-s?*)
                die "Cluster/credential overrides are disabled in the lab wrapper." ;;
        esac
    done
    [ "${1:-}" != "config" ] || die "Use kubectl config directly for configuration management outside the lab wrapper."
    kubectl --context="$PROFILE" "$@"
}
node() {
    if [ "${1:-}" = "--node" ]; then
        [ "$#" -ge 2 ] || die "A node name is required."
        local target=$2
        case "$target" in cks-lab|cks-lab-m02) ;; *) die "Only lab nodes can be selected." ;; esac
        shift 2
        minikube -p "$PROFILE" ssh --node="$target" -- "$@"
    else
        minikube -p "$PROFILE" ssh -- "$@"
    fi
}
lock_lab() {
    mkdir -p "$STATE_DIR"
    if [ ! -e "$STATE_DIR/.gitignore" ]; then
        printf "*\n!.gitignore\n" > "$STATE_DIR/.gitignore"
    fi
    mkdir "$STATE_DIR/lock" 2>/dev/null || die "Another lab operation is active; inspect .cks-state/lock if a previous run was interrupted."
    trap 'rmdir "$STATE_DIR/lock"' EXIT
}
require_lab() {
    need minikube
    need kubectl
    [ -s "$STATE_DIR/cluster-uid" ] || die "No managed session. Use ./k8s-sim.sh start first."
    local actual_uid
    actual_uid=$(k get ns kube-system -o jsonpath='{.metadata.uid}' --request-timeout=15s) || die "Lab API unavailable; no changes made."
    [ -n "$actual_uid" ] && [ "$actual_uid" = "$(cat "$STATE_DIR/cluster-uid")" ] || die "Profile ownership mismatch; refusing to use this cluster."
}

save_cluster_uid() {
    need python3
    python3 - "$STATE_DIR/cluster-uid" "$1" <<'PY'
import os, pathlib, re, sys, tempfile
target, value = pathlib.Path(sys.argv[1]), sys.argv[2]
if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}', value):
    sys.exit('Invalid namespace identity; no ownership record was written.')
descriptor, name = tempfile.mkstemp(prefix='.cluster-uid-', dir=target.parent)
try:
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(value + '\n')
    os.replace(name, target)
finally:
    if os.path.exists(name):
        os.unlink(name)
PY
}

recover_lab_identity() {
    # Recover only our fixture-marked node, never adopt an arbitrary profile
    # merely because it has the expected name. Read its identity independently
    # of the host kubeconfig, then require both connections to agree.
    [ ! -L "$STATE_DIR/cluster-uid" ] || die "Ownership record is a symlink; existing profile was retained."
    local verified_uid context_uid
    verified_uid=$(node 'set -eu
# CKS_IDENTITY_RECOVERY: read-only verification inside the Minikube profile.
[ "$(cat /opt/cks-lab/fixture-marker)" = cks-lab-fixtures-v1 ] || exit 1
client=/usr/local/bin/kubectl
if [ ! -x "$client" ]; then
    client=
    for candidate in /var/lib/minikube/binaries/v*/kubectl; do
        if [ -x "$candidate" ]; then client=$candidate; break; fi
    done
fi
[ -n "$client" ] || exit 1
sudo "$client" --kubeconfig=/etc/kubernetes/admin.conf get namespace kube-system --request-timeout=15s -o jsonpath="{.metadata.uid}"') || die "Cannot verify the existing profile as this simulator; profile and answers were retained."
    verified_uid=${verified_uid//$'\r'/}
    context_uid=$(k get ns kube-system -o jsonpath='{.metadata.uid}' --request-timeout=15s) || die "Lab API unavailable during identity recovery; profile and answers were retained."
    [ -n "$verified_uid" ] && [ "$verified_uid" = "$context_uid" ] || die "Host context does not match the verified lab node; profile and answers were retained."
    save_cluster_uid "$verified_uid"
    echo "Recovered missing session identity from the verified simulator node."
}

clear_session_state() {
    rm -f -- "$STATE_DIR/cluster-uid" "$STATE_DIR/deadline" "$STATE_DIR/setup-complete" "$STATE_DIR/mode" "$STATE_DIR/exam-expected.json"
}
delete_owned_lab() {
    require_lab
    echo "Removing the previous owned Minikube profile $PROFILE..."
    minikube -p "$PROFILE" delete
    clear_session_state
}
