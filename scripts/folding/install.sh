#!/usr/bin/env bash
# Install folding@home from the AUR on a CachyOS / Arch box.
# Builds the package, installs it, enables and starts the service.
# Does NOT write a passkey or team — that is done by configure.sh.
# Requires: base-devel, git, an active internet connection, sudo access.
#
# Usage:
#   ./install.sh                # build and install
#   ./install.sh --no-start     # build + install, leave the service stopped
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
for arg in "$@"; do
    case "${arg}" in
        --no-start) start_service=0 ;;
        -h|--help)
            sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# *//'
            exit 0
            ;;
        *) echo "Unknown arg: ${arg}" >&2; exit 2 ;;
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

if (( start_service )); then
    echo
    echo ">>> Enabling and starting fah-client.service"
    sudo systemctl enable --now fah-client.service
    sleep 2
    echo
    echo "Service status:"
    systemctl is-active fah-client.service
fi

echo
echo "Done. Next:"
echo "  1. Get a passkey from https://apps.foldingathome.org/passkey (one per"
echo "     user, valid across machines)."
echo "  2. Save it to ~/.config/foldingathome/passkey on this machine"
echo "     (chmod 600; the file is gitignored by cachyos-setup)."
echo "  3. Run ./configure.sh to write /etc/fah-client/config.xml with your"
echo "     team (223518, Linus Tech Tips) and machine name, then restart the"
echo "     service with:  sudo systemctl restart fah-client.service"
echo
echo "Monitor at any time:"
echo "  ./status.sh                          # service + WU summary"
echo "  http://localhost:7396/               # web control panel"
