#!/usr/bin/env bash
# Updates the saved campus login password (and optionally the username).
# Usage: update-password.sh [--username]
set -euo pipefail
umask 077

DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/auto-login/config"

# Read the current username from the config (same format login.sh parses).
current_user=""
if [ -r "$CONF" ]; then
  current_user=$(sed -n 's/^[[:space:]]*USERNAME[[:space:]]*=[[:space:]]*//p' "$CONF" | head -n1)
  current_user="${current_user%\"}"; current_user="${current_user#\"}"
  current_user="${current_user%\'}"; current_user="${current_user#\'}"
fi

user="$current_user"
if [ -z "$user" ] || [ "${1:-}" = "--username" ]; then
  read -rp "Username${current_user:+ [$current_user]}: " u
  user="${u:-$current_user}"
fi
[ -n "$user" ] || { echo "Username cannot be empty" >&2; exit 1; }

read -rsp "New password: " p1; echo
read -rsp "Confirm password: " p2; echo
[ -n "$p1" ] || { echo "Password cannot be empty" >&2; exit 1; }
[ "$p1" = "$p2" ] || { echo "Passwords do not match; nothing changed" >&2; exit 1; }

mkdir -p "$(dirname "$CONF")"
chmod 700 "$(dirname "$CONF")"
tmp=$(mktemp "$CONF.XXXXXX")
printf 'USERNAME=%s\nPASSWORD=%s\n' "$user" "$p1" > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$CONF"
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/auto-login/failures"   # un-pause login.sh
echo "Saved to $CONF"

read -rp "Test the login now? [y/N] " t
if [[ "$t" =~ ^[Yy]$ ]]; then
  "$DIR/login.sh" --force --notify
fi
