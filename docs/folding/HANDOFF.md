# Folding@home — handoff and runbook

This document covers the cachyos-setup folding@home module: install, configure, run, monitor, and troubleshoot the `fah-client` AUR package on a CachyOS / Arch box. The repo is set up to fold for **team 223518 (Linus Tech Tips)** on every machine that checks it out.

## 1. What the module does

The scripts in `scripts/folding/` turn a fresh CachyOS box into a folding@home client in three steps:

| Step | Script | What it does |
|---|---|---|
| 1 | `install.sh` | clones the `foldingathome` AUR package, builds it, installs it, enables and starts `fah-client.service` |
| 2 | (manual) | user pastes their 32-hex FAH passkey into `~/.config/foldingathome/passkey` (chmod 600) |
| 3 | `configure.sh` | reads the passkey + this machine's hostname, writes `/etc/fah-client/config.xml` with team=223518, user=`<hostname>-folding`, GPU auto-detection, and restarts the service |

After that, `status.sh` gives a one-screen overview at any time, and the FAHClient web control panel is reachable on `http://localhost:7396/`.

## 2. The 30-second version

```bash
cd scripts/folding
./install.sh                                                     # 3-10 min build
mkdir -p ~/.config/foldingathome && chmod 700 ~/.config/foldingathome
umask 077 && ${EDITOR:-nano} ~/.config/foldingathome/passkey      # paste passkey
./configure.sh                                                    # write config, restart
./status.sh                                                       # verify
```

The passkey is **one per user, not one per machine**. Every box you fold from uses the same passkey; the per-machine `user` field in `config.xml` is what keeps each box's points separate in the team stats.

If you need the passkey later, the box will still fold for the team but your points will be credited to "Anonymous" until you add it. The web control panel will nag about it.

## 3. Where things live

| Path | Owner | Purpose |
|---|---|---|
| `/usr/bin/fah-client` | root (from AUR package) | the folding client binary |
| `/etc/fah-client/config.xml` | `fah-client` user | live config; written by `configure.sh`, never committed |
| `/var/lib/fah-client/` | `fah-client` user | WU state, work cache |
| `/var/log/fah-client/log.txt` | `fah-client` user | rolling client log; primary debugging source |
| `~/.config/foldingathome/passkey` | you (chmod 600) | the real FAH passkey; **gitignored**, never committed |
| `scripts/folding/passkey.example` | repo | 33-char template, not a real key |
| `http://localhost:7396/` | the running service | web control panel (CPU/GPU priorities, pause, per-slot config) |

## 4. Per-machine username

Default is `<hostname>-folding` — e.g. `cachyos-taichi-folding`. Each box in the fleet folds under its own name so the LTT team page shows per-machine contributions. Override per machine with:

```bash
FOLDING_USER=taichi-big ./configure.sh
```

The username only needs to be unique inside team 223518; it can be anything reasonable (e.g. `hs-taichi-gpu`, `laptop-folding`, `server-room-3`).

## 5. GPU vs CPU

`configure.sh` calls `nvidia-smi` to count GPUs. If it finds any, it adds one `<slot type="GPU">` per GPU to `config.xml`. The script defaults to GPU folding whenever a GPU is present.

Override per box:

```bash
FOLDING_GPU=0 ./configure.sh    # CPU only (e.g. headless server)
FOLDING_GPU=1 ./configure.sh    # force GPU folding even if nvidia-smi is missing
```

To use the GPU effectively, make sure the closed-source NVIDIA driver is installed (`nvidia-dkms` on CachyOS, or `nvidia` from extra), and the OpenCL ICD loader (`opencl-nvidia` or `ocl-icd`).

For an AMD/Intel GPU, install `opencl-mesa` and `ocl-icd`. FAHClient will pick it up automatically; no edit to `config.xml` is needed.

## 6. Power level

`config.xml` is written with `<power v="MEDIUM"/>`. This is the recommended default:

- **FULL** — runs at max TDP, max points. Heats the room, spins fans, slows interactive use.
- **MEDIUM** — full speed when the system is idle, backs off when you're using it. Best balance for a desktop.
- **LIGHT** — gentle throttling. Good for laptops on battery or shared workstations.
- **PAUSED** — does not start new WUs, finishes the current one.

To change it on the fly without re-running the script, use the web control panel: *Configure → Power*.

## 7. Monitoring

### 7.1 Command line

```bash
cd scripts/folding
./status.sh
```

shows service state, recent log, current config, and machine identity (hostname, GPU, user).

For a live refresh:

```bash
watch -n30 ./status.sh
```

### 7.2 Web control panel

Local: open <http://localhost:7396/> in a browser. From another box:

```bash
ssh -L 7396:localhost:7396 user@this-host
```

then open <http://localhost:7396/> on the laptop.

### 7.3 Public team stats

- Team 223518: <https://apps.foldingathome.org/team/223518> (overall rank, score, WU count)
- Per-user breakdown (your machines): <https://apps.foldingathome.org/folds/per-user/> (after the first WUs complete, ~10-30 min)
- Per-machine view: click any username on the team page to see its WU history.

## 8. Troubleshooting

### 8.1 Service won't start

```bash
sudo systemctl status fah-client.service
sudo journalctl -u fah-client.service -n 50
```

Common causes:

- `config.xml` is invalid XML — re-run `./configure.sh`.
- passkey file is wrong / not 32 hex — `configure.sh` will refuse to start; the passkey check fails fast.
- port 7396 is in use by something else — `sudo ss -ltn | grep 7396`. Stop the other listener or change FAHClient's `web-allow` and `web-bind` in `config.xml`.

### 8.2 Service starts but no WUs are assigned

Check the log:

```bash
sudo tail -n 50 /var/log/fah-client/log.txt
```

Look for `Server contacted` and `Assigned to work server`. If you see `Server reports work server is overcommitted` and `Going to sleep`, the project is full — wait, it will retry on the back-off. If you see `Could not connect to work server`, check the firewall; fah-client needs outbound TCP 80, 443, and 8080.

### 8.3 WU completes but no points show up on the team page

Points are credited when the WU **server-side** return is accepted, not when the client finishes uploading. The WU shows in your user page right away, but the team score updates on the next 24h batch. If it's been >24h, check `fah-client` log for "Upload completed" + "Server accepted" — if you only see the first line, the work server rejected the return (common on low-quality hosts or if a slot was misconfigured).

### 8.4 Mac RDP crash still happening

(folding module unrelated — see `docs/rdp/RDP-HANDOFF.md` §3.8.)

## 9. Per-machine list

Tracked in `SETUP.md` §"Machines running this" — keep it up to date as boxes are added or retired. When a box stops folding, points stop accruing under that name within ~5 minutes of the service exiting.

## 10. References

- Folding@home main: <https://foldingathome.org/>
- Team 223518 (Linus Tech Tips): <https://apps.foldingathome.org/team/223518>
- Get a passkey: <https://apps.foldingathome.org/passkey>
- AUR `foldingathome` package: <https://aur.archlinux.org/packages/foldingathome>
- fah-client source: <https://github.com/foldingathome/fah-client-bastet>
