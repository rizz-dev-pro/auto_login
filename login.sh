#!/usr/bin/env bash
# Logs in to the IIT (ISM) captive portal if the network is not already authenticated.
# Usage: login.sh [--force] [--notify]
set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/auto-login/config"
PORTAL="https://netaccess.iitism.ac.in:6082"
CHECK_URL="https://connectivitycheck.gstatic.com/generate_204"

force=0; notify=0
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --notify) notify=1 ;;
  esac
done

say() {
  echo "$*"
  if [ "$notify" = 1 ] && command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Auto Login" "Network login" "$*"
  fi
  return 0
}

command -v curl >/dev/null 2>&1 || { say "curl is required but not installed"; exit 1; }

online() {
  [ "$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$CHECK_URL" 2>/dev/null || true)" = "204" ]
}

# Safely parse config without evaluating arbitrary shell code
parse_config() {
  local conf_file="$1"
  [ -r "$conf_file" ] || return 1
  local re="^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \#* | "") continue ;;
    esac
    if [[ "$line" =~ $re ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      # Strip matched enclosing quotes if present
      if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      case "$key" in
        USERNAME) USERNAME="$val" ;;
        PASSWORD) PASSWORD="$val" ;;
      esac
    fi
  done < "$conf_file"
}

[ -r "$CONF" ] || { say "Missing config: $CONF"; exit 1; }

USERNAME=""
PASSWORD=""
parse_config "$CONF"

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  say "Error: USERNAME or PASSWORD is missing or empty in $CONF"
  exit 1
fi

# Failed-attempt counter: stops the timer from hammering the portal with a wrong password.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/auto-login"
FAIL_FILE="$STATE_DIR/failures"
MAX_FAILS=3
fails=0
if [ -r "$FAIL_FILE" ]; then
  if [ "$CONF" -nt "$FAIL_FILE" ]; then
    rm -f "$FAIL_FILE"   # credentials were edited since the last failure
  else
    fails=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
  fi
fi
[[ "$fails" =~ ^[0-9]+$ ]] || fails=0

if [ "$force" = 0 ] && online; then
  rm -f "$FAIL_FILE"
  [ "$notify" = 1 ] && say "Already logged in"
  exit 0
fi

# --force (the hotkey) bypasses the pause for a manual retry.
if [ "$force" = 0 ] && [ "$fails" -ge "$MAX_FAILS" ]; then
  say "Login paused after $MAX_FAILS failed attempts; run update-password.sh or press the hotkey"
  exit 3
fi

# Ask the portal where it wants us; fall back to building the URL from our own IP.
# Note: neverssl.com is queried via plain HTTP intentionally to trigger captive portal redirection.
redirect=$(curl -s -m 8 -o /dev/null -w '%{redirect_url}' http://neverssl.com 2>/dev/null || true)
case "$redirect" in "$PORTAL"/*) ;; *) redirect="";; esac

if [ -n "$redirect" ]; then
  # Securely follow redirect with TLS verification enabled
  form_url=$(curl -s -m 8 -L "$redirect" -o /dev/null -w '%{url_effective}' 2>/dev/null || true)
else
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' || true)
  if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    form_url="$PORTAL/?src=$ip&url=http%3A%2F%2Fneverssl.com%2F"
  else
    form_url="$PORTAL/"
  fi
fi

# Validate that form_url strictly targets the legitimate portal domain over HTTPS
case "$form_url" in
  "$PORTAL"/* | "$PORTAL") ;;
  *)
    say "Security warning: aborting login, unexpected redirect target: $form_url"
    exit 1
    ;;
esac

# Secure POST with TLS verification enabled (prevents credential interception)
# || true ensures network errors/timeouts do not trigger set -e before showing the failure notification
post_code=$(curl -s -S -m 15 -o /dev/null -w '%{http_code}' "$form_url" -X POST \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD" || true)

sleep 2
if online; then
  rm -f "$FAIL_FILE"
  say "Logged in"
else
  # Only count it when the portal actually answered; an unreachable portal/network isn't a bad password.
  if [ "$post_code" != "000" ]; then
    [ "$fails" -ge "$MAX_FAILS" ] || fails=$((fails + 1))
    mkdir -p "$STATE_DIR"
    echo "$fails" > "$FAIL_FILE"
    if [ "$fails" -ge "$MAX_FAILS" ]; then
      echo "Login paused after $MAX_FAILS failed attempts"
      if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "Auto Login" "Network login paused" \
          "$MAX_FAILS failed attempts. Run update-password.sh, or press the hotkey to retry."
      fi
    fi
  fi
  say "Login failed (attempt $fails/$MAX_FAILS; check credentials / portal)"
  exit 2
fi
