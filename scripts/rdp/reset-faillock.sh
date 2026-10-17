#!/usr/bin/env bash
# reset-faillock.sh - clear pam_faillock lockouts for the current user.
#
# Why this exists: CachyOS's pam_faillock locks an account after 3 failed
# logins in 15 minutes and holds the lock for ~10 minutes. KRDP auth
# failures count, and Mac RDP clients (see docs/rdp/RDP-HANDOFF.md §3.6)
# easily rack up 3+ wrong-password attempts in a row because they cache
# stale credentials. After that, even the correct password is rejected
# until the lock window passes or you run this.
#
# Usage:
#   ./reset-faillock.sh            # clear lockout for $USER
#   ./reset-faillock.sh alice      # clear lockout for a specific user
#
# Requires sudo (interactive prompt).

set -euo pipefail

USER_TO_RESET="${1:-$USER}"

if ! command -v faillock >/dev/null 2>&1; then
    echo "faillock not found (install 'pam' or 'util-linux' on non-CachyOS)." >&2
    exit 1
fi

echo "Before:"
faillock --user "$USER_TO_RESET" || true
echo
echo "Resetting faillock for '$USER_TO_RESET'..."
sudo faillock --user "$USER_TO_RESET" --reset
echo
echo "After:"
faillock --user "$USER_TO_RESET" || true
echo
echo "Done. You should be able to log in again now."
