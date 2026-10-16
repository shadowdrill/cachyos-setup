# Plasma Wayland KRDP RDP Handoff

## Goal

Enable RDP access to the active CachyOS Plasma Wayland session using KDE KRDP.

## System state

| Component | Version |
|---|---|
| Plasma | 6.7.5 |
| `plasma-desktop` | 6.7.5-1.1 |
| `krdp` | 6.7.5-1.1 |
| `freerdp` | 3.32.2-1.1 |

No newer versions for these packages are currently reported by `pacman -Qu`.

## Installed and running

- `krdp` is installed from `cachyos-extra-znver4`.
- The KRDP user service is active:
  ```bash
  systemctl --user status app-org.kde.krdpserver.service
  ```
- It listens on TCP port 3389:
  ```bash
  ss -ltnp | grep ':3389'
  ```
- Remote Desktop is configured through:
  ```bash
  kcmshell6 kcm_krdpserver
  ```
- KRDP configuration is in:
  ```text
  ~/.config/krdpserverrc
  ```

## Current Remote Desktop UI configuration

Screenshot: `Screenshot_20261015_104354.png`

- RDP server enabled.
- LAN address shown: `192.168.0.101`
- Port: `3389`
- System user `hs` is enabled under **System Users**, which should authenticate with the normal local account password.
- A manually-created `test` user remains under **Other Users**. It should be removed because it was only a diagnostic account and does not authenticate.
- The previous duplicate manually-created `hs` account was removed.

Configuration values currently show:

```bash
kreadconfig6 --file krdpserverrc --group General --key Users
# test

kreadconfig6 --file krdpserverrc --group General --key SystemUserEnabled --default false
# true
```

## Failure

Every RDP client attempt fails during NLA/CredSSP authentication. KRDP logs:

```text
[ERROR][com.winpr.sspi.NTLM] - [ntlm_fetch_ntlm_v2_hash]:
Error: Could not find user in SAM database
[ERROR][com.freerdp.core.auth] - [credssp_auth_authenticate]:
AcceptSecurityContext status SEC_E_NO_CREDENTIALS [0x8009030e]
[ERROR][com.freerdp.core.transport] - [transport_accept_nla]:
client authentication failure
```

Logs:

```bash
journalctl --user -u app-org.kde.krdpserver.service --since '30 minutes ago' --no-pager
```

## Important reproduction

The failure is reproducible without the KDE settings module, KWallet, the LAN, or the external RDP client:

1. Started a temporary localhost-only KRDP server with explicit temporary credentials:
   ```bash
   krdpserver --plasma --address 127.0.0.1 --port 3390 \
     --username testprobe --password '<temporary-password>'
   ```
2. Tried to authenticate locally:
   ```bash
   xfreerdp3 /v:127.0.0.1:3390 /u:testprobe \
     /p:'<temporary-password>' /cert:ignore /auth-only
   ```
3. It failed with `ERRCONNECT_LOGON_FAILURE`; the temporary server produced the same
   `Could not find user in SAM database` error.
4. Retesting with explicit RDP domains (`.`, `localhost`, and empty) made no difference.

This indicates the problem is below the Plasma Remote Desktop configuration: an apparent KRDP/FreeRDP NLA authentication compatibility or package defect.

## Findings already ruled out

- KRDP is installed and actively listening on port 3389.
- The server restarts after settings changes.
- The RDP client reaches KRDP.
- The System Settings module is present and has the expected **Usernames** UI.
- System-user/PAM authentication is enabled for `hs`.
- Saved manually-created user credentials did not load into KRDP.
- Removing the duplicate manual `hs` user did not fix NLA authentication.
- There are no newer RDP stack packages and no older FreeRDP package in `/var/cache/pacman/pkg`.

## Suggested next investigation

1. Remove the remaining diagnostic `test` entry from **Other Users**.
2. Look for an upstream KRDP issue involving Plasma/KRDP 6.7.5 and FreeRDP 3.32.2,
   especially `ntlm_fetch_ntlm_v2_hash` and `Could not find user in SAM database`.
3. Determine whether CachyOS’s `freerdp 3.32.2-1.1` needs a KRDP compatibility patch,
   or whether testing a newer KRDP/FreeRDP build resolves the issue.
4. If native RDP remains blocked, use a workaround:
   - Sunshine + Moonlight for the existing Wayland desktop, or
   - `xrdp` with an Xorg/XFCE session (not the current Plasma Wayland session).

## Resolution (2026-10-15)

Root cause: FreeRDP 3.32 (commit a1fad13) changed `FreeRDP_ExtSecurity` (PROTOCOL_HYBRID_EX)
to default TRUE. KRDP 6.7.5 only disables `NlaSecurity`, so the server negotiated HYBRID_EX
(CredSSP/NTLM) instead of KRDP's TLS + PAM path, and NTLM had no SAM database -> failure.
Upstream fix: KRDP commit 573e40a on Plasma/6.7 ("Fix authentication with FreeRDP 3.32", KDE bug 526514).

Fix applied: rebuilt krdp 6.7.5 as `krdp 6.7.5-3` (Release build) from `scripts/rdp/krdp-build/PKGBUILD` with
the ExtSecurity patch plus a `DOMAIN\user` username fix, replaced the 1-day TLS cert with a 10-year
one, and set `AutogenerateCertificates=false`. Verified: Windows mstsc logs in as `hs`.

Follow-ups:
- No IgnorePkg needed: 6.7.5-3 sorts above the repo build, and krdp 6.8.0 will replace it.
- Remove the diagnostic `test` user from Other Users in the Remote Desktop settings.
- Full details: `SETUP.md` and `KRDP-Remote-Desktop-Guide.docx`.

## Update (2026-10-16): Plasma 6.8

After upgrading to Plasma 6.8.0, login worked but Windows showed a black screen. krdp 6.8.0's new
video flow control stalled when Windows suspended frame acknowledgements (KDE BUG 520260). Fixed by
building krdp 6.8.1 from KDE's Plasma/6.8 release commit 5813706 (`scripts/rdp/krdp-build/PKGBUILD`), installed
as `krdp 6.8.1-1`. The CachyOS 6.8.1 package will replace it automatically. See `SETUP.md`.
