#!/usr/bin/env bash
# Decrypt a GPG-symmetric-encrypted passkey file and install it at
# $XDG_CONFIG_HOME/foldingathome/passkey (chmod 600, dir mode 700).
#
# This is the counterpart to committing passkey.gpg: instead of carrying the
# 32-hex key in plaintext, you encrypt it once with a passphrase and commit
# the .gpg file. On every new box, run this script and type the passphrase
# (or pipe it via --passphrase-file for non-interactive use).
#
# Usage:
#   ./seed-passkey.sh                                # use the default path
#                                                  # (../passkey.gpg next to
#                                                  #  this script), prompt
#   ./seed-passkey.sh --from <path.gpg>              # explicit source
#   ./seed-passkey.sh --to   <path>                  # explicit dest (default
#                                                  # ~/.config/foldingathome/passkey)
#   ./seed-passkey.sh --passphrase-file <path>       # non-interactive
#   ./seed-passkey.sh --check                        # exit 0 if dest already
#                                                  # has a valid 32-hex key
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_FROM="${SCRIPT_DIR}/passkey.gpg"
DEFAULT_TO="${XDG_CONFIG_HOME:-$HOME/.config}/foldingathome/passkey"

from_path="${DEFAULT_FROM}"
to_path="${DEFAULT_TO}"
passphrase_file=""
check_only=0
force=0
while (( $# > 0 )); do
    case "${1}" in
        --from)             from_path="${2:-}"; shift 2 ;;
        --from=*)           from_path="${1#--from=}"; shift ;;
        --to)               to_path="${2:-}"; shift 2 ;;
        --to=*)             to_path="${1#--to=}"; shift ;;
        --passphrase-file)  passphrase_file="${2:-}"; shift 2 ;;
        --passphrase-file=*) passphrase_file="${1#--passphrase-file=}"; shift ;;
        --check)            check_only=1; shift ;;
        --force)            force=1; shift ;;
        -h|--help)
            sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# *//'
            exit 0
            ;;
        *) echo "Unknown arg: ${1}" >&2; exit 2 ;;
    esac
done

# --- check-only path: exit 0 if dest already has a valid 32-hex key ---
if (( check_only )); then
    if [[ -s "${to_path}" ]] && tr -d '[:space:]' < "${to_path}" | grep -qE '^[A-Fa-f0-9]{32}$'; then
        exit 0
    fi
    exit 1
fi

# --- preconditions ---
if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root; the script writes to your home dir." >&2
    exit 1
fi
if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg not found. Install it:  sudo pacman -S --needed gnupg" >&2
    exit 1
fi
if [[ ! -s "${from_path}" ]]; then
    cat <<EOF >&2
No encrypted passkey file at ${from_path}.

To create one (one-time, on any box that already has the plaintext key):

  gpg --batch --yes --pinentry-mode loopback --passphrase '' \\
      --symmetric --cipher-algo AES256 \\
      -o scripts/folding/passkey.gpg ~/.config/foldingathome/passkey

(replace '' with your passphrase, or run gpg --symmetric interactively and
type it when prompted. The ciphertext goes in scripts/folding/passkey.gpg,
which is safe to commit because it is passphrase-protected.)

Re-run this script after committing the .gpg file.
EOF
    exit 1
fi

# --- skip if dest already has a valid key, unless --force ---
if (( ! force )) && [[ -s "${to_path}" ]]; then
    if tr -d '[:space:]' < "${to_path}" | grep -qE '^[A-Fa-f0-9]{32}$'; then
        echo "${to_path} already has a valid 32-hex passkey; leaving it. (Use --force to overwrite.)"
        exit 0
    fi
    echo "${to_path} exists but does not look like a 32-hex passkey; will overwrite." >&2
fi

# --- ensure the dest dir exists with mode 700 ---
to_dir="$(dirname "${to_path}")"
mkdir -p "${to_dir}"
chmod 700 "${to_dir}"

# --- decrypt to a temp file in the same dir, then atomically move ---
tmp="$(mktemp "${to_dir}/.passkey.tmp.XXXXXXXX")"
chmod 600 "${tmp}"
trap 'rm -f "${tmp}"' EXIT

gpg_args=(
    --batch
    --yes
    --decrypt
    --output "${tmp}"
)

if [[ -n "${passphrase_file}" ]]; then
    # --passphrase-file reads from a file; safer than --passphrase on argv
    if [[ ! -s "${passphrase_file}" ]]; then
        echo "Passphrase file ${passphrase_file} is empty or missing." >&2
        exit 1
    fi
    chmod 600 "${passphrase_file}" 2>/dev/null || true
    gpg_args+=(--passphrase-file "${passphrase_file}")
    # --pinentry-mode loopback only when a passphrase is provided non-interactively
    gpg_args+=(--pinentry-mode loopback)
else
    # Let gpg prompt the user (TTY-based pinentry)
    :
fi

# Show the user what we're about to do, but not the passphrase.
echo ">>> Decrypting ${from_path} -> ${to_path}"

if ! gpg "${gpg_args[@]}" "${from_path}"; then
    rm -f "${tmp}"
    echo "gpg decryption failed (bad passphrase, or corrupted file)." >&2
    exit 1
fi

# --- validate the decrypted content is 32 hex chars ---
plaintext="$(tr -d '[:space:]' < "${tmp}")"
if [[ ! "${plaintext}" =~ ^[A-Fa-f0-9]{32}$ ]]; then
    rm -f "${tmp}"
    echo "Decrypted content is not 32 hex characters; aborting." >&2
    exit 1
fi

# --- atomic install (rename within the same filesystem) ---
mv "${tmp}" "${to_path}"
chmod 600 "${to_path}"
trap - EXIT   # success: leave the file in place

echo
echo "Wrote 32-hex passkey to ${to_path} (mode 600, dir mode 700)"
echo "Next:  ./configure.sh"
