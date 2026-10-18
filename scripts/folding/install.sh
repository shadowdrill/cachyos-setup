#!/usr/bin/env bash
# Install folding@home on a CachyOS / Arch or Ubuntu 24 box.
# Detects the distro and dispatches to the right per-distro installer
# (install-arch.sh for Arch-family, install-ubuntu.sh for Debian-family).
# Also creates the per-user config dir at ~/.config/foldingathome/ (mode 700)
# and optionally writes the 32-hex passkey there (mode 600).
# Team config (id, username, slots) is written by configure.sh.
#
# Usage:
#   ./install.sh                                # build/install, no passkey yet
#   ./install.sh --passkey <32hex>              # also seed the passkey file
#   ./install.sh --passkey-file <path>          # read passkey from an existing file
#   ./install.sh --seed-passkey                 # decrypt scripts/folding/passkey.gpg
#                                             # (committed) and write the key
#   ./install.sh --seed-passkey --from <path>   # use a different .gpg file
#   ./install.sh --seed-passkey --passphrase-file <path>
#                                             # non-interactive (e.g. on a
#                                             # scripted fleet rollout)
#   ./install.sh --no-start                     # install but leave service stopped
#   ./install.sh --run-configure                # also run configure.sh at the end
#
# One-time setup of the encrypted passkey (on any box that already has the
# plaintext key):
#   gpg --batch --yes --pinentry-mode loopback --passphrase '<your passphrase>' \\
#       --symmetric --cipher-algo AES256 \\
#       -o scripts/folding/passkey.gpg ~/.config/foldingathome/passkey
#   git add scripts/folding/passkey.gpg && git commit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- arg parser (shared: every per-distro installer sees the same flags) ---
start_service=1
passkey_arg=""
passkey_file_arg=""
seed_passkey=0
seed_from=""
seed_passphrase_file=""
run_configure=0
# while loop (not for) so `shift` inside the body affects the next iteration
while (( $# > 0 )); do
    case "${1}" in
        --no-start)             start_service=0; shift ;;
        --passkey)              passkey_arg="${2:-}"; shift 2 ;;
        --passkey=*)            passkey_arg="${1#--passkey=}"; shift ;;
        --passkey-file)         passkey_file_arg="${2:-}"; shift 2 ;;
        --passkey-file=*)       passkey_file_arg="${1#--passkey-file=}"; shift ;;
        --seed-passkey)         seed_passkey=1; shift ;;
        --from)                 seed_from="${2:-}"; shift 2 ;;
        --from=*)               seed_from="${1#--from=}"; shift ;;
        --passphrase-file)      seed_passphrase_file="${2:-}"; shift 2 ;;
        --passphrase-file=*)    seed_passphrase_file="${1#--passphrase-file=}"; shift ;;
        --run-configure)        run_configure=1; shift ;;
        -h|--help)
            sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# *//'
            exit 0
            ;;
        *) echo "Unknown arg: ${1}" >&2; exit 2 ;;
    esac
done

# --- preflight: not root, sudo + gpg (if --seed-passkey) available ---
if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root; the script will sudo when it needs to." >&2
    exit 1
fi
if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found; this script expects a sudo-capable user." >&2
    exit 1
fi
if (( seed_passkey )) && ! command -v gpg >/dev/null 2>&1; then
    echo "gpg not found; install it (e.g. 'sudo pacman -S gnupg' or 'sudo apt install gnupg')." >&2
    exit 1
fi

# --- pre-create the per-user config dir early so --passkey works even if
# the install below fails. Folding a mkdir under $HOME is safe. ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/foldingathome"
PASSKEY_FILE="${CONFIG_DIR}/passkey"
mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"

# --- distro detection: pick the per-distro installer ---
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
fi
DISTRO_ID="${ID:-unknown}"
DISTRO_INSTALLER=""
case "${DISTRO_ID}" in
    cachyos|arch|archarm|manjaro|endeavouros|garuda|artix)
        DISTRO_INSTALLER="${SCRIPT_DIR}/install-arch.sh"
        DISTRO_LABEL="Arch / CachyOS"
        ;;
    ubuntu|debian|linuxmint|pop|elementary|zorin|kubuntu|edubuntu|neon)
        DISTRO_INSTALLER="${SCRIPT_DIR}/install-ubuntu.sh"
        DISTRO_LABEL="Ubuntu / Debian"
        ;;
    *)
        echo "Unsupported distro: ${DISTRO_ID:-unknown} (PRETTY_NAME='${PRETTY_NAME:-}')." >&2
        echo "Supported families: Arch / CachyOS (install-arch.sh) and Ubuntu / Debian (install-ubuntu.sh)." >&2
        echo "You can run one of those scripts directly if you know what you're doing." >&2
        exit 1
        ;;
esac

if [[ ! -r "${DISTRO_INSTALLER}" ]]; then
    echo "Per-distro installer not found: ${DISTRO_INSTALLER}" >&2
    exit 1
fi

echo ">>> Detected ${DISTRO_LABEL} (id=${DISTRO_ID})"
echo ">>> Running ${DISTRO_INSTALLER##*/}"
# Source the installer so it shares our env. Each installer uses
# `return 1` on failure so the error propagates back to us.
. "${DISTRO_INSTALLER}"

# --- write the passkey, if one was provided ---
passkey_written=0
if [[ -n "${passkey_file_arg}" ]]; then
    if [[ ! -s "${passkey_file_arg}" ]]; then
        echo "Passkey file ${passkey_file_arg} is empty or missing." >&2
        exit 1
    fi
    passkey_arg="$(tr -d '[:space:]' < "${passkey_file_arg}")"
fi
if [[ -n "${passkey_arg}" ]]; then
    if [[ ! "${passkey_arg}" =~ ^[A-Fa-f0-9]{32}$ ]]; then
        echo "Passkey must be exactly 32 hex characters; got: ${passkey_arg}" >&2
        exit 1
    fi
    (umask 077 && printf '%s\n' "${passkey_arg}" > "${PASSKEY_FILE}")
    chmod 600 "${PASSKEY_FILE}"
    passkey_written=1
    echo
    echo "Wrote passkey to ${PASSKEY_FILE} (mode 600, gitignored)"
fi

# --- or, decrypt the committed passkey.gpg into the passkey file ---
if (( seed_passkey )); then
    if [[ ! -x "${SCRIPT_DIR}/seed-passkey.sh" ]]; then
        echo "seed-passkey.sh not found next to install.sh; cannot --seed-passkey." >&2
        exit 1
    fi
    seed_args=()
    [[ -n "${seed_from}" ]]             && seed_args+=(--from "${seed_from}")
    [[ -n "${seed_passphrase_file}" ]]  && seed_args+=(--passphrase-file "${seed_passphrase_file}")
    if ! "${SCRIPT_DIR}/seed-passkey.sh" "${seed_args[@]}"; then
        echo "Failed to seed passkey from encrypted file." >&2
        exit 1
    fi
    passkey_written=1
fi

if (( start_service )); then
    echo
    echo ">>> Enabling and starting fah-client.service"
    sudo systemctl enable --now fah-client.service
    sleep 2
    echo
    echo "Service status:"
    systemctl is-active fah-client.service
fi

if (( run_configure )) && [[ -x "${SCRIPT_DIR}/configure.sh" ]]; then
    if (( passkey_written )) || [[ -s "${PASSKEY_FILE}" ]]; then
        echo
        echo ">>> Running configure.sh"
        exec "${SCRIPT_DIR}/configure.sh"
    else
        echo
        echo "--run-configure requested but no passkey is in ${PASSKEY_FILE} yet."
        echo "Re-run with --passkey <32hex> --run-configure, --passkey-file <path> --run-configure,"
        echo "or --seed-passkey --run-configure."
        exit 1
    fi
fi

echo
if (( passkey_written )); then
    echo "Done. Next:"
    echo "  ./configure.sh                  # write /etc/fah-client/config.xml"
    echo "                                  # (team 223518, machine name, GPU slots)"
    echo "                                  # and restart the service."
else
    echo "Done. Next:"
    echo "  1. Get a passkey from https://apps.foldingathome.org/passkey (one per"
    echo "     user, valid across machines)."
    echo "  2. Save it to ${PASSKEY_FILE} (chmod 600; the file is gitignored)."
    echo "     This dir already exists with mode 700; just drop the file in."
    echo "  3. Run ./configure.sh to write /etc/fah-client/config.xml with your"
    echo "     team (223518, Linus Tech Tips) and machine name, then restart the"
    echo "     service with:  sudo systemctl restart fah-client.service"
    echo
    echo "  Alternative: commit scripts/folding/passkey.gpg (gpg --symmetric) and"
    echo "  use --seed-passkey on new machines so the plaintext is never typed again."
fi
echo
echo "Monitor at any time:"
echo "  ./status.sh                          # service + WU summary"
echo "  http://localhost:7396/               # web control panel"
