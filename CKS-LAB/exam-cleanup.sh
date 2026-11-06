#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
lock_lab
delete_owned_lab
echo "Cleanup complete. Other profiles and Kubernetes configuration directories are preserved."
