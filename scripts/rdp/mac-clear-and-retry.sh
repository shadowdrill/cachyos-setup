#!/usr/bin/env bash
# mac-clear-and-retry.sh - one-shot helper to clear the Microsoft Remote
# Desktop keychain cache, reset the CachyOS faillock, and tail the krdp log.
#
# Run this on the MAC (not the CachyOS box) from Terminal.app. It will:
#   1. Quit Microsoft Remote Desktop if it's running.
#   2. Delete the keychain entries that MRD has cached for the CachyOS
#      box's IP/hostname (forces a fresh password prompt next time).
#   3. SSH into the CachyOS box, reset the pam_faillock lockout, and tail
#      the krdp log live so you can see whether the next MRD attempt
#      succeeds.
#
# Prerequisites on the Mac: `ssh` and `security` (built-in), and a working
# SSH connection to the CachyOS box (key-based, or you'll be prompted for
# the Linux password and the sudo password — both are the same).
#
# Usage:
#   ./mac-clear-and-retry.sh                                  # uses default IP 192.168.0.101
#   ./mac-clear-and-retry.sh 192.168.0.42 cachyos-taichi      # custom IP + hostname

set -euo pipefail

HOST_IP="${1:-192.168.0.101}"
HOST_NAME="${2:-cachyos-taichi}"
LINUX_USER="${3:-hs}"

echo ">>> Target: ${LINUX_USER}@${HOST_IP}  (hostname: ${HOST_NAME})"
echo

# Step 1: quit Microsoft Remote Desktop so its keychain entries are flushable.
if pgrep -fq "Microsoft Remote Desktop"; then
    echo ">>> Quitting Microsoft Remote Desktop..."
    osascript -e 'quit app "Microsoft Remote Desktop"' 2>/dev/null || true
    sleep 2
fi

# Step 2: clear the keychain entries for this host. Two kinds are stored:
#   - kind "application password" (the actual saved RDP password)
#   - with the host's IP or hostname as the "service" name
echo ">>> Searching Keychain for cached credentials for ${HOST_IP} / ${HOST_NAME}..."
ENTRIES=$(security dump-keychain 2>/dev/null \
    | awk -v ip="$HOST_IP" -v name="$HOST_NAME" '
        /"svce"<blob>=/ { svce=$0 }
        /"acct"<blob>=/ { acct=$0 }
        /"class"<blob>=/ { class=$0 }
        /"desc"<blob>=/ { desc=$0 }
        /"agrp"<blob>=/ { agrp=$0; in_entry=1 }
        in_entry && (svce ~ ip || svce ~ name) && class ~ "genp" { print svce; in_entry=0 }
        in_entry && /^}/ { in_entry=0; svce=""; acct=""; class=""; desc=""; agrp="" }')

if [[ -z "$ENTRIES" ]]; then
    # Easier: ask the user to open Keychain Access and clear manually.
    echo "    No exact match in keychain. Opening Keychain Access for manual review..."
    open -a "Keychain Access"
    echo "    In Keychain Access: search for '${HOST_IP}' or '${HOST_NAME}',"
    echo "    then delete the entries with kind 'application password' or 'internet password'."
    echo "    Then come back here and press Enter to continue."
    read -r _
else
    # We found at least one match. Wipe it via the security CLI.
    echo ">>> Found cached entries. Deleting..."
    # Iterate the keychain and remove matching generic-password items.
    while read -r svce; do
        security delete-generic-password -s "$svce" 2>/dev/null \
            || security delete-internet-password -s "$svce" 2>/dev/null \
            || true
    done <<<"$ENTRIES"
    echo "    Done."
fi

echo
echo ">>> Resetting faillock on ${HOST_IP} and tailing the krdp log..."
echo "    (you'll be asked for the Linux password; sudo on the box uses the same one)"
echo "    --- press Ctrl-C to exit the log tail ---"
echo

# Step 3: reset the lockout and tail the log. -t forces a tty so sudo
# can prompt for the password; -o StrictHostKeyChecking=accept-new lets
# the user's first connection to a new box proceed without a yes/no
# prompt; -o UserKnownHostsFile=~/... keeps that only for this call.
exec ssh -tt \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    "${LINUX_USER}@${HOST_IP}" \
    "sudo faillock --user ${LINUX_USER} --reset; \
     echo '>>> Lockout reset. Watching krdp log... (Ctrl-C to exit)'; \
     journalctl --user -u app-org.kde.krdpserver.service -f"
