#!/usr/bin/env bash
# Ubuntu 24.04 (and Debian 12+) install path for folding@home.
# Downloads the official .deb straight from Folding@home's downloads CDN
# and uses `apt install ./file.deb` to handle dependencies automatically.
#
# This script is sourced by ../install.sh; it can also be run directly for
# testing (in which case it pre-creates the per-user config dir itself).
#
# Notes on the package version: the .deb on the official download server is
# the FAH stable line (currently 8.1.x), not the 8.5.x that the Arch AUR
# builds. Both work for folding; the 8.5.x AUR package is built from the
# newer bastet branch upstream. If you specifically want 8.5.x on Ubuntu,
# build from source against https://github.com/foldingathome/fah-client-bastet
# (out of scope for this script).
#
# Requirements: curl or wget, sudo, an active internet connection, amd64
# or arm64. Assumes the user is NOT root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- distro / arch detection ---
# Honor a test override (FAH_TEST_OS_RELEASE=/path/to/release) so the
# install path can be smoke-tested on non-Ubuntu boxes. Production callers
# just leave the env var unset and get the normal /etc/os-release source.
if [[ -n "${FAH_TEST_OS_RELEASE:-}" && -r "${FAH_TEST_OS_RELEASE}" ]]; then
    . "${FAH_TEST_OS_RELEASE}"
else
    . /etc/os-release
fi
DISTRO_ID="${ID:-unknown}"
DISTRO_VERSION="${VERSION_ID:-unknown}"
case "${DISTRO_ID}" in
    ubuntu)
        if [[ "${DISTRO_VERSION%%.*}" -lt 22 ]]; then
            echo "Ubuntu ${DISTRO_VERSION} is older than 22.04; this script is tested on 24.04." >&2
            echo "Try anyway? (Will continue in 5s; Ctrl-C to abort.)" >&2
            sleep 5
        fi
        ;;
    debian)
        echo "Debian detected. This script is tested on Ubuntu 24.04; Debian 12+ should also work." >&2
        ;;
    *)
        echo "install-ubuntu.sh: unsupported distro id '${DISTRO_ID}'." >&2
        echo "This script is for Ubuntu (and Debian); use install-arch.sh on Arch-family." >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)         DEB_PATH="debian-stable-64bit/release"  ;;
    aarch64|arm64)  DEB_PATH="debian-stable-arm64/release"  ;;
    *)
        echo "install-ubuntu.sh: unsupported architecture '${ARCH}'." >&2
        echo "Folding@home ships debs for x86_64 and aarch64 only." >&2
        return 1 2>/dev/null || exit 1
        ;;
esac
DEB_URL="https://download.foldingathome.org/releases/public/fah-client/${DEB_PATH}/latest.deb"

# --- preflight: need a downloader and apt ---
need_install=()
for tool in curl wget; do
    command -v "${tool}" >/dev/null 2>&1 && break
done
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Neither curl nor wget found; need at least one." >&2
    return 1 2>/dev/null || exit 1
fi
if ! command -v apt >/dev/null 2>&1 && ! command -v apt-get >/dev/null 2>&1; then
    echo "apt/apt-get not found; this script targets Debian-family." >&2
    return 1 2>/dev/null || exit 1
fi
if ! dpkg --version >/dev/null 2>&1; then
    echo "dpkg not found; this script targets Debian-family." >&2
    return 1 2>/dev/null || exit 1
fi

# --- download the latest .deb into a temp dir ---
TMP_DEB="$(mktemp -d -t fah-deb.XXXXXXXX)"
TMP_DEB_FILE="${TMP_DEB}/fah-client.deb"
trap 'rm -rf "${TMP_DEB}"' EXIT

echo ">>> Downloading ${DEB_URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "${TMP_DEB_FILE}" "${DEB_URL}"
else
    wget -q --tries=3 --timeout=30 -O "${TMP_DEB_FILE}" "${DEB_URL}"
fi

if [[ ! -s "${TMP_DEB_FILE}" ]]; then
    echo "Downloaded file is empty or missing." >&2
    return 1 2>/dev/null || exit 1
fi

# Confirm it's actually a Debian package before sudoing
if ! file "${TMP_DEB_FILE}" | grep -qi 'Debian binary package'; then
    echo "Downloaded file does not look like a .deb; got:" >&2
    file "${TMP_DEB_FILE}" >&2
    head -c 200 "${TMP_DEB_FILE}" >&2
    echo >&2
    return 1 2>/dev/null || exit 1
fi

echo ">>> Installing fah-client (and any missing deps) with apt"
# `apt install ./file.deb` is the modern way; it auto-fetches deps from the
# configured apt sources and doesn't leave the package in a half-installed
# state if something is missing. Falls back to apt-get on minimal systems.
if command -v apt >/dev/null 2>&1; then
    sudo apt install -y "${TMP_DEB_FILE}"
else
    sudo apt-get install -y "${TMP_DEB_FILE}"
    sudo apt-get -f install -y   # belt-and-suspenders for any orphan deps
fi

echo
echo "Installed:"
dpkg -l fah-client | tail -1
which fah-client
systemctl cat fah-client.service 2>/dev/null | head -3 || echo "(service file not present yet)"
id fah-client 2>/dev/null || echo "(fah-client user not present yet)"

# Clean up the .deb; the package is now in dpkg's database
rm -rf "${TMP_DEB}"
trap - EXIT
