# folding@home module

CachyOS-side scripts for joining the [Linus Tech Tips folding@home team](https://apps.foldingathome.org/team/223518) (id **223518**) on every box that has this repo checked out. Each machine folds independently under the same passkey, with a unique per-machine username, so points track per-machine in the LTT team ranking.

## One-time per machine

```bash
cd scripts/folding

# 1. Install the FAHClient package from the AUR (needs sudo; builds from source, ~3-10 min).
#    Pass --passkey to seed the per-user key at the same time, or --run-configure
#    to chain the configure step too.
./install.sh [--passkey <32hex> | --passkey-file <path>] [--run-configure]

# 2. If you didn't pass --passkey in step 1: get one at
#    https://apps.foldingathome.org/passkey (one per user, valid on every machine)
#    and drop it in ~/.config/foldingathome/passkey (the dir is mode 700, the file
#    must be mode 600).
mkdir -p ~/.config/foldingathome && chmod 700 ~/.config/foldingathome
umask 077
${EDITOR:-nano} ~/.config/foldingathome/passkey     # paste the 32-hex passkey, save

# 3. Write /etc/fah-client/config.xml (team=223518, user=<hostname>-folding, auto-detect GPU)
./configure.sh

# 4. Verify
./status.sh
```

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
| `install.sh` | build + install from AUR | yes |
| `configure.sh` | write `/etc/fah-client/config.xml` | yes |
| `status.sh` | one-screen service + WU summary | yes |
| `passkey` (example below) | template only | yes (template) |
| `~/.config/foldingathome/passkey` | real 32-hex passkey | **no — gitignored** |
| `/etc/fah-client/config.xml` | live FAHClient config | managed by the system, not in this repo |

## Why a per-machine username

If you set every machine to `hs-folding`, the LTT team page shows you as one contributor and you can't tell which box is doing the work. The default `<hostname>-folding` keeps each machine's WUs and points separately attributed. You can see the per-machine breakdown at <https://apps.foldingathome.org/folds/per-user/> after the first few WUs complete.

## Tuning

`config.xml` currently sets `<power v="MEDIUM"/>` which is the right balance for a desktop: full speed when idle, throttles when the box is busy. Change to `FULL` for max points (impacts system responsiveness), or `LIGHT` for laptops on battery.

See `docs/folding/HANDOFF.md` for the full setup, troubleshooting, and the list of which machines in the fleet are running this.
