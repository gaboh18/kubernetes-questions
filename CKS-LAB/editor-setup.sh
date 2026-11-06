#!/bin/bash
# Configure editors only in the verified lab profile.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
require_lab
configure_editor() {
    echo "Configuring Vim on $1..."
    node --node "$1" 'set -eu
if ! command -v vim >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1 || { echo "Vim is missing and apt-get is unavailable." >&2; exit 1; }
    sudo apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends vim
fi
printf "export EDITOR=vim\nexport VISUAL=vim\nexport KUBE_EDITOR=vim\n" | sudo tee /etc/profile.d/cks-lab-editor.sh >/dev/null
vim --version | head -1'
}
configure_editor cks-lab
if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
    configure_editor cks-lab-m02
fi
