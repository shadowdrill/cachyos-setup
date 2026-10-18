#!/usr/bin/env bash
# Quick status check for the folding@home client on this machine.
# Shows: service state, current WU + progress + ETA, points accrued since
# startup, and the config that is in /etc/fah-client/config.xml.
#
# Usage:
#   ./status.sh                 # one-shot
#   watch -n30 ./status.sh      # refresh every 30s
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== fah-client service ==="
if systemctl is-active --quiet fah-client.service 2>/dev/null; then
    echo "active   ($(systemctl show -p ActiveEnterTimestamp --value fah-client.service))"
else
    echo "INACTIVE — start with:  sudo systemctl start fah-client.service"
    systemctl is-enabled fah-client.service 2>/dev/null | sed 's/^/  enabled: /'
fi

echo
echo "=== process ==="
pgrep -af fah-client | sed 's/^/  /' || echo "  (no fah-client process)"

echo
echo "=== recent log (last 15 lines) ==="
if [[ -r /var/log/fah-client/log.txt ]]; then
    tail -n 15 /var/log/fah-client/log.txt | sed 's/^/  /'
else
    sudo journalctl -u fah-client.service --no-pager -n 15 2>&1 | sed 's/^/  /'
fi

echo
echo "=== config in /etc/fah-client/config.xml ==="
if [[ -f /etc/fah-client/config.xml ]]; then
    grep -E '<(user|team|passkey|power|cause)' /etc/fah-client/config.xml | sed 's/^/  /'
    echo
    echo "  slots:"
    grep -E '<slot|<cpus' /etc/fah-client/config.xml | sed 's/^/    /'
fi

echo
echo "=== machine identity ==="
echo "  hostname:  $(hostname)"
echo "  user:      $(whoami)"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name --format=csv,noheader 2>/dev/null | sed 's/^/  gpu:      /'
else
    echo "  gpu:      (no nvidia-smi; CPU only)"
fi
