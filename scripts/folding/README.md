# folding@home module

Scripts for joining the [Linus Tech Tips folding@home team](https://apps.foldingathome.org/team/223518) (id **223518**) on every box that has this repo checked out. Each machine folds independently under the same passkey, with a unique per-machine username, so points track per-machine in the LTT team ranking.

## Supported distros

`install.sh` auto-detects the distro via `/etc/os-release` and dispatches to the right per-distro installer:

| Distro | Installer | How fah-client is packaged |
|---|---|---|
| CachyOS, Arch, Manjaro, EndeavourOS, Garuda, Artix | `install-arch.sh` | AUR `foldingathome` package (8.5.x), built from source via `makepkg` |
| Ubuntu 22.04+, Debian 12+, Linux Mint, Pop!_OS, elementary, Zorin, KDE Neon | `install-ubuntu.sh` | official `.deb` from <https://download.foldingathome.org/releases/public/fah-client/> (stable line, 8.1.x) |

The rest of the module (`configure.sh`, `status.sh`, `seed-passkey.sh`) is distro-agnostic — the upstream fah-client package, service, and config paths are the same on both.

> **Version note:** the AUR package is on FAH's 8.5.x line (bastet branch), the official `.deb` is on the 8.1.x stable line. Both fold. If you specifically want 8.5.x on Ubuntu, build `fah-client-bastet` from source — out of scope for this module.

## One-time per machine

The passkey is a per-user secret that's the same across every machine in the
fleet. There are two ways to get it onto a new box; pick one:

**A. Decrypt the committed `passkey.gpg` (preferred for fleet rollouts):**
```bash
cd scripts/folding
./install.sh --seed-passkey --run-configure
# ...prompts for the passphrase (or --passphrase-file <path> for scripted)
```

**B. Type/paste the passkey on the new machine:**
```bash
cd scripts/folding
./install.sh [--passkey <32hex> | --passkey-file <path>] [--run-configure]
# or, after the package is installed:
./configure.sh     # will prompt you to paste the passkey if missing
```

The full flow (used by either path):

```bash
cd scripts/folding

# 1. Install the FAHClient package from the AUR (needs sudo; builds from source, ~3-10 min).
./install.sh --seed-passkey --run-configure

# 2. Verify
./status.sh
```

If `configure.sh` runs and finds no passkey in `~/.config/foldingathome/passkey`
AND a `passkey.gpg` next to itself, it will try to decrypt that automatically
before erroring out.

## Setting up `passkey.gpg` (one-time, on any box that has the plaintext key)

```bash
cd scripts/folding
gpg --batch --yes --pinentry-mode loopback \
    --passphrase '<your passphrase>' \
    --symmetric --cipher-algo AES256 \
    -o passkey.gpg ~/.config/foldingathome/passkey
git add passkey.gpg
git commit -m "folding: rotate GPG-encrypted passkey"
```

The file is **not** in `.gitignore` — it should be committed, that's the
point. The passphrase is the only thing protecting the secret.

To rotate the passphrase later, just re-encrypt and commit again. To rotate
the passkey itself, get a new one from
<https://apps.foldingathome.org/passkey>, drop it into
`~/.config/foldingathome/passkey`, re-encrypt, commit.

## Day-to-day

| What | Command |
|---|---|
| Service state, WU, log | `./status.sh` |
| Web control panel (local) | open <http://localhost:7396/> |
| Web control panel (remote) | `ssh -L 7396:localhost:7396 user@host` then open the URL on your laptop |
| Restart after config change | `sudo systemctl restart fah-client.service` |
| Pause / resume | `sudo systemctl stop fah-client.service` / `sudo systemctl start fah-client.service` |
| Disable on this machine (e.g. laptop on battery) | `sudo systemctl disable --now fah-client.service` |
| Per-machine name (overrides default `<hostname>-folding`) | `FOLDING_USER=taichi-gpu ./configure.sh` |
| Force CPU-only (no GPU slot) | `FOLDING_GPU=0 ./configure.sh` |
| Force GPU folding even if detection is unsure | `FOLDING_GPU=1 ./configure.sh` |

## Files

| Path | Purpose | Committed? |
|---|---|---|
| `install.sh` | dispatcher: detects distro, sources the right per-distro installer, runs shared post-install | yes |
| `install-arch.sh` | AUR build path (CachyOS / Arch family) | yes |
| `install-ubuntu.sh` | apt path (Ubuntu / Debian family); downloads official `.deb` from Folding@home | yes |
| `configure.sh` | write `/etc/fah-client/config.xml` (distro-agnostic) | yes |
| `seed-passkey.sh` | decrypt `passkey.gpg` to `~/.config/foldingathome/passkey` (distro-agnostic) | yes |
| `status.sh` | one-screen service + WU summary (distro-agnostic) | yes |
| `passkey.example` | template only | yes |
| `passkey.gpg` | GPG-symmetric-encrypted passkey, committed | yes (if you create it; see §11) |
| `~/.config/foldingathome/passkey` | real 32-hex passkey | **no — gitignored** |
| `/etc/fah-client/config.xml` | live FAHClient config | managed by the system, not in this repo |

## Why a per-machine username

If you set every machine to `hs-folding`, the LTT team page shows you as one contributor and you can't tell which box is doing the work. The default `<hostname>-folding` keeps each machine's WUs and points separately attributed. You can see the per-machine breakdown at <https://apps.foldingathome.org/folds/per-user/> after the first few WUs complete.

## Tuning

`config.xml` currently sets `<power v="MEDIUM"/>` which is the right balance for a desktop: full speed when idle, throttles when the box is busy. Change to `FULL` for max points (impacts system responsiveness), or `LIGHT` for laptops on battery.

See `docs/folding/HANDOFF.md` for the full setup, troubleshooting, and the list of which machines in the fleet are running this.
