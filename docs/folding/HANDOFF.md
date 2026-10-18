# Folding@home — handoff and runbook

This document covers the cachyos-setup folding@home module: install, configure, run, monitor, and troubleshoot the `fah-client` client on a CachyOS / Arch or Ubuntu 24 box. The repo is set up to fold for **team 223518 (Linus Tech Tips)** on every machine that checks it out.

## 1. What the module does

The scripts in `scripts/folding/` turn a fresh box into a folding@home client in three steps:

| Step | Script | What it does |
|---|---|---|
| 1 | `install.sh` | detects the distro via `/etc/os-release` and dispatches to `install-arch.sh` (AUR build) or `install-ubuntu.sh` (downloads the official `.deb`); enables and starts `fah-client.service` |
| 2 | (key) | the 32-hex FAH passkey is decrypted from a GPG-encrypted `passkey.gpg` (committed) into `~/.config/foldingathome/passkey` (chmod 600) |
| 3 | `configure.sh` | reads the passkey + this machine's hostname, writes `/etc/fah-client/config.xml` with team=223518, user=`<hostname>-folding`, GPU auto-detection, and restarts the service |

After that, `status.sh` gives a one-screen overview at any time, and the FAHClient web control panel is reachable on `http://localhost:7396/`.

## 1.1 Supported distros

| Distro family | Installer | Package source | fah-client version |
|---|---|---|---|
| CachyOS, Arch, Manjaro, EndeavourOS, Garuda, Artix | `install-arch.sh` | AUR `foldingathome` (built from source) | 8.5.x (bastet branch) |
| Ubuntu 22.04+, Debian 12+, Linux Mint, Pop!_OS, elementary, Zorin, KDE Neon | `install-ubuntu.sh` | official `.deb` from `download.foldingathome.org` (stable line) | 8.1.x |

Both paths produce the same binary, service, user, and config layout on disk, so `configure.sh`, `status.sh`, and `seed-passkey.sh` are distro-agnostic.

> **Version mismatch:** the AUR is on the newer 8.5.x line (cutting-edge bastet); the official `.deb` is on 8.1.x (older stable). Both fold, but feature parity is not 1:1. If you need 8.5.x on Ubuntu, build `fah-client-bastet` from source — out of scope for this module.

## 2. The 30-second version

```bash
cd scripts/folding
./install.sh --seed-passkey --run-configure
# ...type the passphrase when prompted (or --passphrase-file <path> for scripted)
./status.sh
```

If you don't have `passkey.gpg` yet (e.g. first box, ever), bootstrap with a plaintext paste instead:

```bash
cd scripts/folding
./install.sh --passkey <32hex> --run-configure
```

Or, after install, just run `configure.sh` — it will try to decrypt `passkey.gpg`
itself, and if that fails, prompt for the plaintext key.

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

### 8.5 `install.sh: unsupported distro` on a known-good box

The dispatcher only matches the IDs listed in §1.1. If your distro is on the list but you still get the error:

```bash
cat /etc/os-release | grep ^ID=
```

The match is against `ID=` only; `ID_LIKE=` is ignored. If your distro has a different `ID=` (e.g. `linuxmint` was renamed to `mint`), add it to the case statement in `install.sh`. Common ones already covered: `ubuntu`, `debian`, `linuxmint`, `pop`, `elementary`, `zorin`, `kubuntu`, `edubuntu`, `neon` (Ubuntu derivatives) and `cachyos`, `arch`, `archarm`, `manjaro`, `endeavouros`, `garuda`, `artix` (Arch derivatives).

### 8.6 Ubuntu install: `dpkg: error processing package fah-client`

If `apt install ./fah-client.deb` reports a missing dependency, run:

```bash
sudo apt --fix-broken install
```

and re-run `./install.sh`. The script uses `apt install ./file.deb` instead of raw `dpkg -i` precisely so apt auto-fetches the deps from the configured Ubuntu repos; if your apt sources are misconfigured (e.g. you removed the `universe` component on a minimal install), the auto-fetch will fail. Re-enable `universe` first:

```bash
sudo add-apt-repository universe
sudo apt update
```

### 8.7 `passkey.gpg` was committed by accident with the wrong passphrase

Re-encrypt with the correct passphrase (or with a new key from <https://apps.foldingathome.org/passkey>) and `git commit --amend`. If the file is already in a remote (e.g. GitHub), the previous ciphertext is recoverable from the git history — rotate the FAH passkey itself in that case.

## 9. Per-machine list

Tracked in `SETUP.md` §"Machines running this" — keep it up to date as boxes are added or retired. When a box stops folding, points stop accruing under that name within ~5 minutes of the service exiting.

## 10. References

- Folding@home main: <https://foldingathome.org/>
- Team 223518 (Linus Tech Tips): <https://apps.foldingathome.org/team/223518>
- Get a passkey: <https://apps.foldingathome.org/passkey>
- AUR `foldingathome` package: <https://aur.archlinux.org/packages/foldingathome>
- fah-client source: <https://github.com/foldingathome/fah-client-bastet>

## 11. Passkey distribution — the GPG-encrypted `passkey.gpg` workflow

The FAH passkey is one per user but every machine in the fleet needs it.
Committing it in plaintext would leak it to anyone with repo read access;
copying it by hand to each box doesn't scale and means the secret appears in
shell history, terminal scrollback, etc. The compromise: commit a GPG-symmetric
encrypted copy of the passkey in the repo, decrypt on each box at install time.

### 11.1 One-time setup (on any box that already has the plaintext key)

```bash
cd scripts/folding

# Choose a passphrase. It only protects the file in git; if you lose it
# you re-encrypt with a new one. Don't reuse your disk-encryption password.
gpg --batch --yes --pinentry-mode loopback \
    --passphrase '<pick a strong passphrase>' \
    --symmetric --cipher-algo AES256 \
    -o passkey.gpg ~/.config/foldingathome/passkey

# Sanity: confirm no plaintext leak
grep -F "$(cat ~/.config/foldingathome/passkey)" passkey.gpg \
    && { echo "FAIL: plaintext leaked"; exit 1; } || echo "ok: no plaintext in .gpg"

git add passkey.gpg
git commit -m "folding: commit GPG-encrypted passkey"
git push
```

Output is ~106 bytes of binary (AES256.CFB). `passkey.gpg` is **not** in
`.gitignore`; it should be committed.

### 11.2 On every new machine (and after a rotation)

```bash
cd scripts/folding
./install.sh --seed-passkey --run-configure
# ...type the passphrase when gpg prompts
```

For non-interactive (fleet rollout, ansible, etc.):

```bash
# write the passphrase to a root-only file, then:
sudo ./install.sh --seed-passkey --passphrase-file /root/.fah-pp --run-configure
# the file should be chmod 600 and lives outside the repo
```

`--seed-passkey` calls `seed-passkey.sh` next to it, which:
- decrypts `passkey.gpg` (or `--from <other path>`) into
  `~/.config/foldingathome/passkey` (mode 600; dir created at mode 700)
- validates the result is exactly 32 hex characters
- aborts (and writes nothing) if gpg fails or the output is wrong

`--run-configure` chains `configure.sh`, which will additionally try to
decrypt `passkey.gpg` itself if it finds the destination empty — that
fallback exists so the workflow keeps working if someone runs `configure.sh`
without going through `install.sh`.

### 11.3 Rotating the passphrase

Re-encrypt the same plaintext with a new passphrase:

```bash
gpg --batch --yes --pinentry-mode loopback \
    --passphrase '<new passphrase>' \
    --symmetric --cipher-algo AES256 \
    -o passkey.gpg ~/.config/foldingathome/passkey
git add passkey.gpg && git commit --amend --no-edit && git push --force
```

(The `--amend` is fine because `passkey.gpg` is the only thing in this
module that's ever updated; if you've made other changes since the initial
commit, just make a new commit.)

### 11.4 Rotating the actual FAH passkey

Get a new one from <https://apps.foldingathome.org/passkey> (re-use the same
email you used the first time), drop the new 32-hex key into
`~/.config/foldingathome/passkey`, then re-run the §11.1 command with the
new key in place. Old box WUs already credited to the previous key are
unaffected.

### 11.5 Threat model and limits

- The GPG passphrase protects against: someone cloning the repo, a public
  GitHub fork, an accidental `git add` in another branch, log/screen-share
  leaks of the on-disk passkey file.
- It does **not** protect against: someone with repo-write access who can
  replace `passkey.gpg` (use signed commits / branch protection for that);
  someone with sudo/root on the box at install time (they can read the
  decrypted file from `~/.config/foldingathome/passkey` anyway).
- The `~/.config/foldingathome/passkey` file ends up mode 600 owned by the
  installing user, which is what fah-client's loader expects.
