# KRDP Remote Desktop: Setup Record

Setup of RDP access to the live Plasma Wayland session on **cachyos-taichi** (`192.168.0.101`), completed 15 October 2026 and updated 16 October 2026 after the Plasma 6.8 upgrade.
For the full user guide (connecting from Windows, the Plasma 6.8 upgrade, troubleshooting), see [`KRDP-Remote-Desktop-Guide.docx`](KRDP-Remote-Desktop-Guide.docx).

## Result

Windows Remote Desktop Connection logs in as `hs` with the normal Linux password and shares the running Plasma session.

| Item | Value |
|---|---|
| Server | KRDP (`krdpserver`), user unit `app-org.kde.krdpserver.service` |
| Address / port | `192.168.0.101:3389` (TCP) |
| Auth mode | System user via PAM (`SystemUserEnabled=true`), TLS transport, no NLA |
| krdp package | `6.8.1-3`, local build of KDE's 6.8.1 release commit + 6d453c8 + 4eb3dff (ahead of CachyOS) |
| freerdp | `3.32.2-1.1` (repo) |
| Plasma | 6.8.0 |

## Root causes and fixes

| # | Problem | Fix |
|---|---|---|
| 1 | FreeRDP 3.32 defaults `FreeRDP_ExtSecurity` to TRUE (commit a1fad13). KRDP 6.7.5 only disables `NlaSecurity`, so clients negotiated HYBRID_EX/NTLM and failed with `Could not find user in SAM database`. | Backported KRDP commit `573e40a` (Plasma/6.7, KDE bug 526514): `ExtSecurity=false`. |
| 2 | Windows sends `PCNAME\hs` / `.\hs`. KRDP 6.7.5 runs PAM only when the username equals `hs` exactly. | Patch strips everything before the last `\` (backport of master `095f6ea`), and logs the rejected username. |
| 3 | The settings page (KCM) generates a **1-day** self-signed cert with no hostname, and regenerates it every time it opens. | New 10-year cert (CN/SAN `cachyos-taichi`, IP `192.168.0.101`), `AutogenerateCertificates=false`. |

## 16 Oct 2026: Plasma 6.8 upgrade

| # | Problem after upgrading to 6.8.0 | Fix |
|---|---|---|
| 4 | Login rejected (`pam_authenticate failure`) | Windows was sending a stale or wrong saved password. Fix: delete saved credentials in mstsc and type the Linux password fresh. 6.8.0 also lacks the `DOMAIN\user` fix, so type exactly `hs`. |
| 5 | **Black screen** after login. x264 encoded 1 keyframe + 5 frames, then stopped. | krdp 6.8.0's new video flow control waits for frame acknowledgements that Windows suspends (`SUSPEND_FRAME_ACKNOWLEDGEMENT`). The in-flight window fills and the stream freezes. KDE BUG 520260, fixed by commit `472584e` on Plasma/6.8. |

Fix: built **krdp 6.8.1** from the Plasma/6.8 release commit `5813706` (tagged upstream 16 Oct 2026, not yet in CachyOS). It includes the frame-ack fix and the mstsc `DOMAIN\user` fix, so no local patches are needed. `vercmp`: the CachyOS `6.8.1-1.1` package will replace this local `6.8.1-1` automatically when it arrives.

## 17 Oct 2026: krdp 6.8.1 + Mac MRD crash

| # | Problem | Fix |
|---|---|---|
| 6 | **krdp crashes with SIGSEGV the moment a Mac MRD client connects.** The Mac sees a generic "We couldn't connect" error; on the box, `journalctl` shows `app-org.kde.krdpserver.service: Main process exited, code=dumped, status=11/SEGV` and a coredump in `freerdp_peer_context_new_ex → freerdp_peer_context_free` (during `RdpConnection::initialize()`). **Windows mstsc is unaffected.** | krdp commit **`6d453c8`** on `Plasma/6.8` (David Edmundson, 2026-10-16, *after* the 6.8.1 release), *"Drop TLS security for non-pam authentication"*. `TlsSecurity` is now gated on `usePamAuthentication` so non-PAM clients take a path that doesn't trigger the use-after-free. **Not enough on its own** — also needed: master commit **`4eb3dff`** (Ben Marshall, 2026-10-01, *"Fix authentication with FreeRDP 3.32"*) which gates `FreeRDP_ExtSecurity` on `!usePamAuthentication`. Without that, freerdp 3.32's default ext security forces `PROTOCOL_HYBRID_EX` and the same use-after-free still fires. |

Build: updated `scripts/rdp/krdp-build/PKGBUILD` to commit `6d453c8` **+ patch** `extsecurity-freerdp-3.32.patch` (cherry-pick of `4eb3dff`), pkgrel `3` → `krdp 6.8.1-3`. Install: `sudo pacman -U krdp-6.8.1-3-x86_64.pkg.tar.zst` then `systemctl --user restart app-org.kde.krdpserver.service`. The CachyOS 6.8.1-1.1 (or 6.8.2) package will replace it once both commits are upstream on `Plasma/6.8`.

Full diagnosis and recovery recipe: see `RDP-HANDOFF.md` §3.8.

Diagnosis tips that worked:

- Frames flowing? Measure server CPU: `P=$(systemctl --user show -p MainPID --value app-org.kde.krdpserver.service); awk '{print $14+$15}' /proc/$P/stat` twice, 3 s apart. A delta of 0 while connected means a stalled stream.
- x264 prints `frame I:/P:` counts when a session ends; a tiny P count means a stall.
- Debug logging via a user drop-in `~/.config/systemd/user/app-org.kde.krdpserver.service.d/debug.conf`:
  ```ini
  [Service]
  Environment="QT_LOGGING_RULES=org.kde.krdp.debug=true;kpipewire_logging.debug=true"
  ```
  Then `systemctl --user daemon-reload && systemctl --user restart app-org.kde.krdpserver.service`. Delete the file when done.

## Repository layout

```
docs/rdp/
├── SETUP.md                         # this file
├── HANDOFF.md                       # original problem handoff + resolution notes
└── KRDP-Remote-Desktop-Guide.docx   # user guide (generated by scripts/rdp/make_guide.py)
scripts/rdp/
├── make_guide.py                    # python-docx script that generates the guide
└── krdp-build/
    ├── PKGBUILD                         # CURRENT: krdp 6.8.1-1 from Plasma/6.8 commit 5813706
    ├── PKGBUILD.6.8.0-2                 # 6.8.0 + username/logging patch (superseded, never installed)
    ├── freerdp-3.32-extsecurity.patch   # 6.7.5 only: upstream 573e40a
    ├── strip-domain-username.patch      # 6.7.5 only: DOMAIN\user fix + failure logging
    └── strip-domain-username-6.8.patch  # 6.8.0 version of the above (superseded by 6.8.1)
```

Build outputs (`src/`, `pkg/`, `*.pkg.tar.zst`) are git-ignored.

## Configuration changed

`~/.config/krdpserverrc`:

```ini
[General]
AutogenerateCertificates=false   # changed: stops the KCM overwriting the cert with a 1-day one
Autostart=true
Certificate=/home/hs/.local/share/krdpserver/krdp.crt
CertificateKey=/home/hs/.local/share/krdpserver/krdp.key
SystemUserEnabled=true
Users=test                       # leftover diagnostic user; remove in System Settings
```

Certificate files are in `~/.local/share/krdpserver/`:

- `krdp.crt` / `krdp.key`: new, valid until 12 Oct 2036
- `krdp.crt.bak-20261015` / `krdp.key.bak-20261015`: original 1-day cert

## Reproducing the setup from scratch

1. Install KRDP and enable it:
   ```bash
   sudo pacman -S krdp
   kcmshell6 kcm_krdpserver     # enable server, tick System User "hs"
   ```
2. Install build dependencies:
   ```bash
   sudo pacman -S --needed cmake extra-cmake-modules plasma-wayland-protocols   # not --asdeps: orphan cleanup removes them
   ```
3. Build and install krdp 6.8.1 (only needed until CachyOS ships krdp ≥ 6.8.1):
   ```bash
   cd scripts/rdp/krdp-build        # from the repository root
   rm -rf src pkg; rm -f *.pkg.tar.zst
   makepkg -f
   sudo pacman -U krdp-6.8.1-1-x86_64.pkg.tar.zst
   systemctl --user restart app-org.kde.krdpserver.service
   ```
4. Create a long-lived certificate and stop auto-generation:
   ```bash
   cd ~/.local/share/krdpserver
   openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
     -keyout krdp.key -out krdp.crt -subj "/CN=$(hostname)" \
     -addext "subjectAltName=DNS:$(hostname),IP:192.168.0.101" \
     -addext "extendedKeyUsage=serverAuth"
   chmod 600 krdp.key
   kwriteconfig6 --file krdpserverrc --group General --key AutogenerateCertificates false
   ```
5. Restart and verify:
   ```bash
   systemctl --user restart app-org.kde.krdpserver.service
   ss -ltn | grep 3389
   journalctl --user -u app-org.kde.krdpserver.service -f
   ```
6. On Windows: `mstsc` → `192.168.0.101`, user `hs`, Linux password, then accept the certificate once with "Don't ask me again".

## Regenerating the Word guide

```bash
python3 -m venv .venv && .venv/bin/pip install python-docx   # once, from the repository root
.venv/bin/python scripts/rdp/make_guide.py                   # writes docs/rdp/KRDP-Remote-Desktop-Guide.docx
```

## Package versioning notes

- Installed: local `krdp 6.8.1-1`. `vercmp 6.8.1-1.1 6.8.1-1` → `1`, so the CachyOS 6.8.1 package (and anything later) replaces it automatically on `pacman -Syu`. That is the intended path.
- Do **not** put krdp in `IgnorePkg`.
- After CachyOS ships its own 6.8.1+, the local build files are no longer needed.

## Status of known KRDP issues (as of 6.8.1)

| Issue | Status | Action |
|---|---|---|
| ExtSecurity / SAM error (FreeRDP 3.32) | Fixed since 6.8.0 | none |
| `DOMAIN\user` username from mstsc | Fixed in 6.8.1 | none |
| Black screen / frozen stream with Windows clients | Fixed in 6.8.1 | none |
| 1-day certificate | Generated only if none is configured | Keep `AutogenerateCertificates=false`; expiry check: `openssl x509 -in ~/.local/share/krdpserver/krdp.crt -noout -enddate` |
| Non-ASCII passwords | Still read as Latin-1 | Keep the password ASCII |
| Empty-password "Other Users" entry | Ends the user check early | Remove the `test` user |
| Hardware H.264 encoding | Not available on the RTX 3090 Ti via VA-API; uses software x264 | Works; costs CPU |

## Gotchas found during the work

- **Debug builds crash on connect.** Without `-DCMAKE_BUILD_TYPE=Release`, a `Q_ASSERT` in `AbstractSession` fires. The official package compiles asserts out.
- **You can't test from the build directory.** KWin only exposes the screencast Wayland protocol to `/usr/bin/krdpserver`, so a binary run from `pkg/` segfaults in `PlasmaScreencastV1Session` when a client connects.
- **faillock.** 3 failed RDP logins lock `hs` (including local login) for about 10 minutes: `faillock --user hs --reset`.
- **`pacman -U` via `!` in Claude Code didn't install.** The sudo prompt didn't go through; run installs in a normal terminal and check `pacman -Q krdp`.
- **Stale saved credentials in mstsc** cause repeated `pam_authenticate failure`. Delete them and type the password fresh.
- **Restart after reinstalling.** `pacman -U` doesn't restart the user service, so the old binary keeps running until you run `systemctl --user restart app-org.kde.krdpserver.service`.
