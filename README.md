# Auto Login

Automatic captive-portal login for the **IIT (ISM) Dhanbad** campus network (`netaccess.iitism.ac.in`). Once installed, you stop seeing the login page: the script checks your connection in the background and logs you in again whenever the session expires.

Works on **Linux** (systemd + optional GNOME hotkey) and **Windows** (Task Scheduler + hotkey).

## Features

- **Hands-free** – runs 15 s after you log in to your session, then every 2 minutes, so session timeouts are handled automatically.
- **Only logs in when needed** – checks connectivity first (`generate_204`) and does nothing if you're already online.
- **Hotkey** – `Ctrl+Alt+L` forces a login immediately and shows a desktop notification.
- **Safe with your credentials**
  - Linux: config stored with `600` permissions in a `700` directory; parsed as plain `KEY=VALUE`, never `source`d.
  - Windows: password encrypted with DPAPI (only your Windows account on that PC can decrypt it).
  - Credentials are only ever sent over HTTPS to `https://netaccess.iitism.ac.in:6082`; any other redirect target aborts the login.
- **Lockout protection** (Linux) – after 3 failed attempts the timer stops retrying so a wrong password doesn't hammer the portal (or get your account locked). Fix it with `update-password.sh`, or press the hotkey to retry manually.

## Linux

### Requirements

- `bash`, `curl`, `ip` (iproute2), `systemd` (user units)
- Optional: `notify-send` (notifications), GNOME's `gsettings` (hotkey)

### Install

```bash
git clone <your-repo-url> auto-login
cd auto-login
./install.sh
```

You'll be asked for your username and password once. The installer then:

1. Saves them to `~/.config/auto-login/config`
2. Creates and enables a systemd user timer (`auto-login.timer`)
3. Registers the `Ctrl+Alt+L` GNOME hotkey (skipped if `gsettings` isn't available)

> Keep the cloned folder where it is – the systemd unit and hotkey point to `login.sh` in it. If you move it, re-run `./install.sh`.

### Usage

| Task | Command |
| --- | --- |
| Log in manually | `./login.sh` |
| Force login, with notification | `./login.sh --force --notify` |
| Change password | `./update-password.sh` |
| Change username and password | `./update-password.sh --username` |
| Check timer status | `systemctl --user status auto-login.timer` |
| View logs | `journalctl --user -u auto-login.service` |
| Uninstall | `./install.sh --uninstall` |

Exit codes of `login.sh`: `0` ok, `1` configuration/security error, `2` login failed, `3` paused after repeated failures.

### Files

| Path | Purpose |
| --- | --- |
| `~/.config/auto-login/config` | `USERNAME=` / `PASSWORD=` |
| `~/.config/systemd/user/auto-login.{service,timer}` | Scheduler units |
| `~/.local/state/auto-login/failures` | Failed-attempt counter |

Uninstalling leaves the config file in place; delete `~/.config/auto-login` if you want it gone.

## Windows

### Requirements

- Windows 10/11 with PowerShell 5.1+

### Install

From the `windows` folder:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

You'll be prompted for username and password (stored encrypted in `%APPDATA%\auto-login\cred.xml`). The installer registers a scheduled task `AutoLogin` (at logon and every 2 minutes, hidden window) and a Start Menu shortcut carrying the `Ctrl+Alt+L` hotkey.

### Usage

```powershell
powershell -ExecutionPolicy Bypass -File login.ps1 -Force -Notify   # manual login
powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall     # remove
```

To change your password, delete `%APPDATA%\auto-login\cred.xml` and run `install.ps1` again.

## How it works

1. Request `https://connectivitycheck.gstatic.com/generate_204`. If it returns `204`, you're online – exit.
2. Request `http://neverssl.com` (plain HTTP on purpose) to trigger the portal redirect and discover the login form URL. If that fails, build the URL from your local IP.
3. Verify the URL is on `https://netaccess.iitism.ac.in:6082`, then `POST` the username and password.
4. Re-check connectivity and report success or failure.

## Troubleshooting

- **"Missing config"** – run `./install.sh` (or `./update-password.sh`) to create it.
- **"Login paused after 3 failed attempts"** – check your password with `./update-password.sh`, or press `Ctrl+Alt+L` to retry.
- **Hotkey doesn't work** – the hotkey is GNOME-only; on other desktops bind `/path/to/login.sh --force --notify` yourself.
- **Nothing happens on a different network** – the script is hard-wired to the IIT (ISM) portal. To adapt it, change `PORTAL` in `login.sh` / `login.ps1`.

## Security note

Your password is stored on disk (plaintext with restricted permissions on Linux, DPAPI-encrypted on Windows). Don't commit your config file, and use this only on a machine you trust.

## Disclaimer

Unofficial tool, not affiliated with IIT (ISM) Dhanbad. Use it in accordance with your institute's network policy.
