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
| AUR package | `foldingathome` 1:8.5.6-1 (built from source by `install.sh`) |
| Service | `fah-client.service` (system, not user) |
| Web UI | `http://localhost:7396/` (forward with `ssh -L 7396:localhost:7396 …`) |

## Install procedure (canonical)

```bash
cd scripts/folding
./install.sh                                                # 3-10 min build, needs sudo
mkdir -p ~/.config/foldingathome && chmod 700 ~/.config/foldingathome
umask 077 && ${EDITOR:-nano} ~/.config/foldingathome/passkey
./configure.sh
./status.sh
```

## Machines running this

| Hostname | IP (LAN) | GPU | Status | First WU | Notes |
|---|---|---|---|---|---|
| cachyos-taichi | 192.168.0.101 | RTX 3090 Ti (24 GB) | not yet installed | — | 9700X 8c/16t, this box |
| _next_ | — | — | — | — | add rows as boxes are folded in |

## Change log

| Date | Change | Why |
|---|---|---|
| 2026-10-18 | initial commit: `install.sh`, `configure.sh`, `status.sh`, `passkey.example`, `README.md`, `HANDOFF.md`, `SETUP.md` | first folding@home setup; uses AUR `foldingathome` 1:8.5.6-1; team 223518 (LTT) |
