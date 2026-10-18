# folding@home — setup log

This file records what was installed, when, and on which machines. It is the "as built" record; `HANDOFF.md` is the how-to.

## Module status (2026-10-18)

| Item | Value |
|---|---|
| Team | **223518** — LinusTechTips_Team (<https://apps.foldingathome.org/team/223518>) |
| Per-machine username pattern | `<hostname>-folding` (override with `FOLDING_USER=…`) |
| Power level (default) | `MEDIUM` |
| GPU detection | `nvidia-smi` if present → one GPU slot per device |
| Config location | `/etc/fah-client/config.xml` (managed by `scripts/folding/configure.sh`) |
| Passkey location | `~/.config/foldingathome/passkey` (chmod 600, **gitignored**) |
| Supported distros | CachyOS / Arch (AUR `foldingathome` 1:8.5.6-1); Ubuntu 22.04+ / Debian 12+ (official `.deb` 8.1.x) |
| Install dispatcher | `install.sh` → `install-arch.sh` OR `install-ubuntu.sh` (chosen by `/etc/os-release`) |
| Service | `fah-client.service` (system, not user) |
| Web UI | `http://localhost:7396/` (forward with `ssh -L 7396:localhost:7396 …`) |

## Install procedure (canonical)

```bash
cd scripts/folding
./install.sh --seed-passkey --run-configure   # 3-10 min build + decrypt + write config
./status.sh
```

The first time, on whatever box already has the plaintext key, also run the
GPG setup once so the rest of the fleet can use `--seed-passkey`:

```bash
gpg --batch --yes --pinentry-mode loopback \
    --passphrase '<pick a strong passphrase>' \
    --symmetric --cipher-algo AES256 \
    -o passkey.gpg ~/.config/foldingathome/passkey
git add passkey.gpg && git commit -m "folding: commit GPG-encrypted passkey"
```

Then on every other box:

```bash
./install.sh --seed-passkey --run-configure
# (or --passphrase-file <path> for non-interactive rollouts)
```

See `HANDOFF.md §11` for the full threat model and rotation procedure.

Fallbacks if `passkey.gpg` isn't (yet) in the repo:

```bash
# If you have the passkey in a file:
./install.sh --passkey-file ~/my-fah-passkey --run-configure

# Or, if you want to type/paste the passkey on this box:
./install.sh --passkey <32hex> --run-configure

# Or, after install, just run configure.sh and it will try to decrypt
# passkey.gpg itself, or prompt for a paste if that fails:
./configure.sh
```

## Machines running this

| Hostname | IP (LAN) | GPU | Status | First WU | Notes |
|---|---|---|---|---|---|
| cachyos-taichi | 192.168.0.101 | RTX 3090 Ti (24 GB) | active, team 223518, user `cachyos-taichi-folding` | pending — server handshake started | 9700X 8c/16t, this box; `fah-client` PID 20589 |
| _next_ | — | — | — | — | add rows as boxes are folded in |

## Change log

| Date | Change | Why |
|---|---|---|
| 2026-10-18 | split install into a dispatcher (`install.sh`) + per-distro installers (`install-arch.sh`, `install-ubuntu.sh`); same shared flags (`--passkey`, `--passkey-file`, `--seed-passkey`, `--from`, `--passphrase-file`, `--no-start`, `--run-configure`); Ubuntu 22.04+ / Debian 12+ support added (downloads official `.deb` from `download.foldingathome.org`); `README.md`, `HANDOFF.md` (new §1.1 distro table, §8.5/§8.6/§8.7 troubleshooting) and `SETUP.md` updated; `FAH_TEST_OS_RELEASE` env var added to `install-ubuntu.sh` to allow smoke-testing the Ubuntu path on non-Ubuntu boxes | first Ubuntu 24 install request; needed the same one-shot UX as the existing CachyOS path |
| 2026-10-18 | added `seed-passkey.sh`; `install.sh` and `configure.sh` now both support `--seed-passkey` / `--from <path>` / `--passphrase-file <path>`; `configure.sh` auto-decrypts `passkey.gpg` as a fallback; `README.md`, `HANDOFF.md` (new §11) and `SETUP.md` updated | keep the FAH passkey out of shell history / unencrypted files / accidental commits, while still letting the repo roll out to a whole fleet with one `./install.sh` command |
| 2026-10-18 | cachyos-taichi now actively folding (PID 20589); `config.xml` populated with team 223518, user `cachyos-taichi-folding`, 1 CPU + 1 GPU slot | first production install of the module |
| 2026-10-18 | `install.sh` now pre-creates `~/.config/foldingathome/` (mode 700) and accepts `--passkey <32hex>` / `--passkey-file <path>` / `--run-configure`; doc updates in `README.md` and `HANDOFF.md` | make install a one-shot when a passkey is already available, instead of a 3-step dance |
| 2026-10-18 | initial commit: `install.sh`, `configure.sh`, `status.sh`, `passkey.example`, `README.md`, `HANDOFF.md`, `SETUP.md` | first folding@home setup; uses AUR `foldingathome` 1:8.5.6-1; team 223518 (LTT) |
