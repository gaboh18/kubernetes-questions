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

clear_session_state() {
    rm -f -- "$STATE_DIR/cluster-uid" "$STATE_DIR/deadline" "$STATE_DIR/setup-complete" "$STATE_DIR/mode" "$STATE_DIR/exam-expected.json"
}
delete_owned_lab() {
    require_lab
    echo "Removing the previous owned Minikube profile $PROFILE..."
    minikube -p "$PROFILE" delete
    clear_session_state
}
