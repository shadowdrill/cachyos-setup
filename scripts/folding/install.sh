#!/usr/bin/env bash
# Install folding@home from the AUR on a CachyOS / Arch box.
# Builds the package, installs it, enables and starts the service.
# Also creates the per-user config dir at ~/.config/foldingathome/ (mode 700)
# and optionally writes the 32-hex passkey there (mode 600).
# Team config (id, username, slots) is written by configure.sh.
# Requires: base-devel, git, gnupg, an active internet connection, sudo access.
#
# Usage:
#   ./install.sh                                # build, install, no passkey yet
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
# plaintext key at ~/.config/foldingathome/passkey):
#   gpg --batch --yes --pinentry-mode loopback --passphrase '<your passphrase>' \\
#       --symmetric --cipher-algo AES256 \\
#       -o scripts/folding/passkey.gpg ~/.config/foldingathome/passkey
#   git add scripts/folding/passkey.gpg && git commit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_BUILD="$(mktemp -d -t foldingathome-build.XXXXXXXX)"
PKG_BUILT=""

cleanup() {
    if [[ -n "${PKG_BUILT}" && -e "${PKG_BUILT}" ]]; then
        rm -f "${PKG_BUILT}"
    fi
    rm -rf "${TMP_BUILD}"
}
trap cleanup EXIT

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
            sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# *//'
            exit 0
            ;;
        *) echo "Unknown arg: ${1}" >&2; exit 2 ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root; the script will sudo when it needs to." >&2
    exit 1
fi
if ! command -v makepkg >/dev/null 2>&1; then
    echo "makepkg not found. Install base-devel first:  sudo pacman -S --needed base-devel" >&2
    exit 1
fi
if ! command -v git >/dev/null 2>&1; then
    echo "git not found. Install it first:  sudo pacman -S --needed git" >&2
    exit 1
fi

# --- pre-create the per-user config dir early so --passkey works even if
# the build below fails. Folding a mkdir under $HOME is safe. ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/foldingathome"
PASSKEY_FILE="${CONFIG_DIR}/passkey"
mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"

echo ">>> Cloning foldingathome from AUR"
git clone --depth 1 https://aur.archlinux.org/foldingathome.git "${TMP_BUILD}/foldingathome"
cd "${TMP_BUILD}/foldingathome"

echo ">>> Building package (this takes 3-10 minutes — scons compiles a lot)"
makepkg -s --noconfirm

# pick the .pkg.tar.* that makepkg just produced
shopt -s nullglob
PKG_FILES=(*.pkg.tar.*)
shopt -u nullglob
if (( ${#PKG_FILES[@]} == 0 )); then
    echo "makepkg did not produce a package; check the output above." >&2
    exit 1
fi
PKG_BUILT="${TMP_BUILD}/foldingathome/${PKG_FILES[0]}"

echo ">>> Installing with pacman"
sudo pacman -U --noconfirm "${PKG_BUILT}"

echo
echo "Installed:"
pacman -Q foldingathome
which fah-client

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
