#!/usr/bin/env bash
# Arch / CachyOS install path for folding@home.
# Clones the foldingathome AUR package, builds it with makepkg, and installs
# the resulting .pkg.tar.* with pacman.
#
# This script is sourced by ../install.sh; it can also be run directly for
# testing (in which case it pre-creates the per-user config dir itself).
#
# Requirements: base-devel (for makepkg), git, sudo, an active internet
# connection. Assumes the user is NOT root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v makepkg >/dev/null 2>&1; then
    echo "makepkg not found. Install base-devel first:  sudo pacman -S --needed base-devel" >&2
    return 1 2>/dev/null || exit 1
fi
if ! command -v git >/dev/null 2>&1; then
    echo "git not found. Install it first:  sudo pacman -S --needed git" >&2
    return 1 2>/dev/null || exit 1
fi

TMP_BUILD="$(mktemp -d -t foldingathome-build.XXXXXXXX)"
PKG_BUILT=""

cleanup() {
    if [[ -n "${PKG_BUILT}" && -e "${PKG_BUILT}" ]]; then
        rm -f "${PKG_BUILT}"
    fi
    rm -rf "${TMP_BUILD}"
}
trap cleanup EXIT

echo ">>> Cloning foldingathome from AUR"
git clone --depth 1 https://aur.archlinux.org/foldingathome.git "${TMP_BUILD}/foldingathome"
(
    cd "${TMP_BUILD}/foldingathome"
    echo ">>> Building package (this takes 3-10 minutes — scons compiles a lot)"
    makepkg -s --noconfirm
)

shopt -s nullglob
PKG_FILES=("${TMP_BUILD}/foldingathome/"*.pkg.tar.*)
shopt -u nullglob
if (( ${#PKG_FILES[@]} == 0 )); then
    echo "makepkg did not produce a package; check the output above." >&2
    return 1 2>/dev/null || exit 1
fi
PKG_BUILT="${PKG_FILES[0]}"

echo ">>> Installing with pacman"
sudo pacman -U --noconfirm "${PKG_BUILT}"

echo
echo "Installed:"
pacman -Q foldingathome
which fah-client
