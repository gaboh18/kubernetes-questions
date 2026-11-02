#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
lock_lab
require_lab
echo "Deleting only the owned Minikube profile $PROFILE. Local exercise files are retained."
minikube -p "$PROFILE" delete
rm -f -- "$STATE_DIR/cluster-uid" "$STATE_DIR/deadline" "$STATE_DIR/setup-complete" "$STATE_DIR/mode"
echo "Cleanup complete. Other profiles and Kubernetes configuration directories are preserved."
