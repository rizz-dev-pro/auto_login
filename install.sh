#!/usr/bin/env bash
set -euo pipefail

# Enforce strict private file permissions for everything created by this script
umask 077

DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/auto-login"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
P=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/auto-login/
S=org.gnome.settings-daemon.plugins.media-keys
K="$S.custom-keybinding:$P"

uninstall() {
  echo "Uninstalling auto-login..."
  systemctl --user stop auto-login.timer auto-login.service 2>/dev/null || true
  systemctl --user disable auto-login.timer 2>/dev/null || true
  rm -f "$UNIT/auto-login.service" "$UNIT/auto-login.timer"
  systemctl --user daemon-reload 2>/dev/null || true

  # Remove GNOME hotkey
  if command -v gsettings >/dev/null 2>&1; then
    gsettings reset-recursively "$K" 2>/dev/null || true
    cur=$(gsettings get $S custom-keybindings 2>/dev/null || echo "[]")
    if [[ "$cur" == *"$P"* ]]; then
      new=$(echo "$cur" | sed -e "s|'$P', ||g" -e "s|, '$P'||g" -e "s|'$P'||g")
      [ "$new" = "[]" ] || [ -z "$new" ] && new="@as []"
      gsettings set $S custom-keybindings "$new" 2>/dev/null || true
    fi
  fi

  echo "Auto-login service and keybindings removed."
  echo "Config remains in $CONF/config (delete manually if desired)."
  exit 0
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
fi

missing=()
for c in curl systemctl ip; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required tools: ${missing[*]}" >&2
  exit 1
fi
command -v notify-send >/dev/null 2>&1 || echo "Warning: notify-send not found; notifications will be skipped."
command -v gsettings >/dev/null 2>&1 || echo "Warning: gsettings not found (not GNOME?); no hotkey will be set up."

mkdir -p "$CONF" "$UNIT"
chmod 700 "$CONF"
chmod +x "$DIR/login.sh"

if [ ! -f "$CONF/config" ]; then
  read -rp "Username: " u
  read -rsp "Password: " p; echo
  printf 'USERNAME=%s\nPASSWORD=%s\n' "$u" "$p" > "$CONF/config"
fi
chmod 600 "$CONF/config"

cat > "$UNIT/auto-login.service" <<UNITEOF
[Unit]
Description=Campus network auto login

[Service]
Type=oneshot
ExecStart="$DIR/login.sh"
UNITEOF

# Runs 15s after your session starts, then every 2 minutes (re-logins after session timeouts).
cat > "$UNIT/auto-login.timer" <<UNITEOF
[Unit]
Description=Campus network auto login (periodic)

[Timer]
OnStartupSec=15
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNITEOF

systemctl --user daemon-reload
systemctl --user enable --now auto-login.timer

# GNOME hotkey: Ctrl+Alt+L
if command -v gsettings >/dev/null 2>&1; then
  gsettings set "$K" name 'Auto Login'
  gsettings set "$K" command "$DIR/login.sh --force --notify"
  gsettings set "$K" binding '<Primary><Alt>l'
  cur=$(gsettings get $S custom-keybindings 2>/dev/null || echo "[]")
  case "$cur" in *"$P"*) ;; *)
    if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then new="['$P']"; else new="${cur%]}, '$P']"; fi
    gsettings set $S custom-keybindings "$new"
    ;;
  esac
fi

if command -v gsettings >/dev/null 2>&1; then
  echo "Installed securely. Timer active; hotkey Ctrl+Alt+L."
else
  echo "Installed securely. Timer active; no hotkey (bind '$DIR/login.sh --force --notify' manually)."
fi
