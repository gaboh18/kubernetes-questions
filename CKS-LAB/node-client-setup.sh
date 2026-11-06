#!/bin/bash
# Make the existing cluster client usable from the verified lab's SSH hosts.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lab-common.sh"
require_lab
need python3
read -r version primary_ip <<< "$(k get node cks-lab -o json --request-timeout=15s | python3 -c '
import ipaddress,json,re,sys
n=json.load(sys.stdin)
v=n["status"]["nodeInfo"]["kubeletVersion"]
if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+",v): sys.exit("Invalid lab node version.")
a=next(a["address"] for a in n["status"]["addresses"] if a["type"]=="InternalIP")
print(v,ipaddress.ip_address(a))
')"
[ -n "$version" ] && [ -n "$primary_ip" ] || die "Could not determine the lab's internal API address."
binary="/var/lib/minikube/binaries/$version/kubectl"
# Read only cluster name/endpoint; certificate and key contents never leave nodes.
connection=$(node --node cks-lab "sudo '$binary' --kubeconfig=/etc/kubernetes/admin.conf config view --minify -o jsonpath='{.contexts[0].context.cluster} {.clusters[0].cluster.server}'")
read -r cluster server <<< "$(printf '%s' "$connection" | python3 -c '
import ipaddress,re,sys,urllib.parse
cluster,endpoint=sys.stdin.read().strip().split()
if not re.fullmatch(r"[a-zA-Z0-9_.:-]+",cluster): sys.exit("Invalid cluster name.")
url=urllib.parse.urlsplit(endpoint)
if url.scheme!="https": sys.exit("The lab API must use HTTPS.")
address=ipaddress.ip_address(sys.argv[1]); host=f"[{address}]" if address.version==6 else str(address)
print(cluster,f"https://{host}:{url.port or 443}")
' "$primary_ip")"
[ -n "$cluster" ] && [ -n "$server" ] || die "Could not determine the lab API endpoint."
# A private configuration directory is used by both the SSH user and root.
prepare_node() {
    node --node "$1" "set -eu
sudo test -x '$binary'
if ! command -v kubectl >/dev/null 2>&1; then sudo ln -sfn '$binary' /usr/local/bin/kubectl; fi
sudo install -d -m 700 -o \"\$(id -u)\" -g \"\$(id -g)\" /opt/cks-lab/client"
}
prepare_node cks-lab
node --node cks-lab 'sudo install -m 600 -o "$(id -u)" -g "$(id -g)" /etc/kubernetes/admin.conf /opt/cks-lab/client/config'
node --node cks-lab "'$binary' --kubeconfig=/opt/cks-lab/client/config config set-cluster '$cluster' --server='$server' >/dev/null"
if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
    prepare_node cks-lab-m02
    minikube -p "$PROFILE" cp 'cks-lab:/opt/cks-lab/client/config' 'cks-lab-m02:/opt/cks-lab/client/config'
fi
configure_node() {
    node --node "$1" 'set -eu
sudo chown "$(id -u):$(id -g)" /opt/cks-lab/client/config
chmod 600 /opt/cks-lab/client/config
mkdir -p "$HOME/.kube"
chmod 700 "$HOME/.kube"
if [ ! -e "$HOME/.kube/config" ] && [ ! -L "$HOME/.kube/config" ]; then
    ln -s /opt/cks-lab/client/config "$HOME/.kube/config"
fi
sudo install -d -m 700 /root/.kube
if ! sudo test -e /root/.kube/config && ! sudo test -L /root/.kube/config; then
    sudo ln -s /opt/cks-lab/client/config /root/.kube/config
fi
printf "export KUBECONFIG=/opt/cks-lab/client/config\n" | sudo tee /etc/profile.d/cks-lab-kubectl.sh >/dev/null
KUBECONFIG=/opt/cks-lab/client/config kubectl get namespace kube-system --request-timeout=15s >/dev/null
sudo env KUBECONFIG=/opt/cks-lab/client/config kubectl get namespace kube-system --request-timeout=15s >/dev/null'
    echo "kubectl is ready on $1 (SSH user and root)."
}
configure_node cks-lab
if [ "$(cat "$STATE_DIR/mode" 2>/dev/null || true)" = exam ]; then
    configure_node cks-lab-m02
fi
