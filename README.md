# Auto Login

Automatic captive-portal login for the **IIT (ISM) Dhanbad** campus network. Once installed, you stop seeing the login page: it runs in the background and logs you in again whenever your session expires.

Works on **Linux** and **Windows**.

## Features

- **Hands-free** – starts when you log in to your computer and keeps you connected.
- **Only logs in when needed** – does nothing if you're already online.
- **Hotkey** – `Ctrl+Alt+L` forces a login immediately.
- **Credentials stay on your machine** – stored locally and only sent to the official campus portal.
- **Lockout protection** (Linux) – stops retrying after a few failed attempts, so a wrong password won't get your account locked.

## Linux

### Install

```bash
git clone https://github.com/rizz-dev-pro/auto_login.git
cd auto_login
./install.sh
```

You'll be asked for your username and password once. Requires `bash`, `curl` and `systemd`; the hotkey needs GNOME.

> Keep the cloned folder where it is. If you move it, re-run `./install.sh`.

### Usage

| Task | Command |
| --- | --- |
| Log in now | `./login.sh --force --notify` |
| Change password | `./update-password.sh` |
| Change username and password | `./update-password.sh --username` |
| View logs | `journalctl --user -u auto-login.service` |
| Uninstall | `./install.sh --uninstall` |

## Windows

Requires Windows 10/11. From the `windows` folder:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

You'll be asked for your username and password once.

| Task | Command |
| --- | --- |
| Log in now | `powershell -ExecutionPolicy Bypass -File login.ps1 -Force -Notify` |
| Change password | Delete `%APPDATA%\auto-login\cred.xml`, then re-run `install.ps1` |
| Uninstall | `powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall` |

## Troubleshooting

- **"Missing config"** – run `./install.sh` (or `./update-password.sh`).
- **"Login paused"** – your password is probably wrong; fix it with `./update-password.sh`, or press `Ctrl+Alt+L` to retry.
- **Hotkey doesn't work** – the Linux hotkey is GNOME-only; on other desktops bind `/path/to/login.sh --force --notify` yourself.

## Security note

Your password is saved on your computer so the tool can log in for you. Use it only on a machine you trust.

## Disclaimer

Unofficial tool, not affiliated with IIT (ISM) Dhanbad. Use it in accordance with your institute's network policy.
