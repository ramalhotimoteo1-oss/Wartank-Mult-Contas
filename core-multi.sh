#!/bin/bash
# core.sh — Funções base v1.1.0 (multi-conta)
#
# Paths por conta — definidos pelo controller ANTES de source:
#   TMP, COOKIE_FILE, CRIPT_FILE, LOG_FILE, SRC, STATUS_FILE, ACC
# Se nao estiverem definidos, usa fallback local (testes).

URL="${URL:-https://wartank-pt.net}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36}"

# Fallback so para debug isolado (controller exporta estes)
BOT_DIR="${BOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TMP="${TMP:-$BOT_DIR/.tmp}"
SRC="${SRC:-$TMP/SRC}"
COOKIE_FILE="${COOKIE_FILE:-$TMP/cookies.txt}"
CRIPT_FILE="${CRIPT_FILE:-$TMP/cript_file}"
LOG_FILE="${LOG_FILE:-$TMP/bot.log}"
STATUS_FILE="${STATUS_FILE:-$TMP/status.txt}"

JSESSIONID="${JSESSIONID:-}"
ACC="${ACC:-}"
FUEL_CURRENT="${FUEL_CURRENT:-}"
PLAYER_LEVEL="${PLAYER_LEVEL:-}"
PLAYER_ID="${PLAYER_ID:-}"
_LOGIN_FAILURES=0

mkdir -p "$TMP"

GOLD='\033[0;33m'
GREEN='\033[32m'
RED='\033[0;31m'
GRAY='\033[02;37m'
RESET='\033[00m'

log() {
  local ts
  printf -v ts '%(%Y-%m-%d %H:%M:%S)T' -1
  echo "[$ts] [${2:-INFO}] $1" >> "$LOG_FILE"
}
log_warn()  { log "$1" "WARN";  echo "[${ACC:-?}] [AVISO] $1"; }
log_error() { log "$1" "ERROR"; echo "[${ACC:-?}] [ERRO]  $1"; }
log_ok()    { log "$1" "OK";    echo "[${ACC:-?}] [OK]    $1"; }

sleep_rand() {
  local min="${1:-300}" max="${2:-1200}" delay
  delay=$(awk -v min="$min" -v max="$max" \
    'BEGIN { srand(); printf "%.3f", (min + rand()*(max-min))/1000 }')
  sleep "${delay}s"
}

_encrypt_creds() {
  local data="$1" out="$2"
  printf '%s' "$data" | base64 -w 0 > "$out"
  chmod 600 "$out"
}

_decrypt_creds() {
  local file="$1"
  [ -f "$file" ] || return 1
  base64 -d "$file" 2>/dev/null
}

_update_jsessionid() {
  local s
  s=$(grep -o -E 'jsessionid=[A-Z0-9]+' "$SRC" 2>/dev/null | head -n1 | sed 's/jsessionid=//')
  [ -n "$s" ] && JSESSIONID="$s"
  # Tambem do cookie file
  if [ -z "$JSESSIONID" ] && [ -f "$COOKIE_FILE" ]; then
    s=$(grep -i 'JSESSIONID' "$COOKIE_FILE" 2>/dev/null | awk '{print $NF}' | tail -n1)
    [ -n "$s" ] && JSESSIONID="$s"
  fi
}

_build_url() {
  local path="$1"
  path=$(echo "$path" | sed 's|^/||;s|;jsessionid=[A-Z0-9]*||')
  local full_url
  if [ -n "$JSESSIONID" ]; then
    if echo "$path" | grep -q '?'; then
      full_url="${URL}/$(echo "$path" | sed "s|?|;jsessionid=${JSESSIONID}?|")"
    else
      full_url="${URL}/${path};jsessionid=${JSESSIONID}"
    fi
  else
    full_url="${URL}/${path}"
  fi
  echo "$full_url" | sed 's|https://||;s|//|/|g;s|^|https://|'
}

_cacert_arg() {
  for ca in \
    /data/data/com.termux/files/usr/etc/tls/cert.pem \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt; do
    [ -f "$ca" ] && { echo "--cacert $ca"; return; }
  done
  echo ""
}

fetch_page() {
  local path="$1"
  local output="${2:-$SRC}"
  local full_url cacert
  full_url=$(_build_url "$path")
  cacert=$(_cacert_arg)

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 --retry 2 --retry-delay 2 \
    $cacert \
    -o "$output" \
    "$full_url" 2>>"$LOG_FILE"

  [ ! -s "$output" ] && log "fetch vazio: $path" "WARN"
  _update_jsessionid
  sleep_rand 300 700
}

fetch_page_fast() {
  local path="$1"
  local output="${2:-$SRC}"
  local full_url cacert
  full_url=$(_build_url "$path")
  cacert=$(_cacert_arg)

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 --retry 1 \
    $cacert \
    -o "$output" \
    "$full_url" 2>>"$LOG_FILE"

  [ ! -s "$output" ] && log "fetch_fast vazio: $path" "WARN"
  _update_jsessionid
}

_session_active() {
  local f="${1:-$SRC}"
  grep -q 'user=0;level=0' "$f" 2>/dev/null && return 1
  grep -q 'IFormSubmitListener-loginForm\|showSigninLink' "$f" 2>/dev/null && return 1
  grep -q 'user=[1-9]\|title>Hangar\|title>Escolta\|title>Base' "$f" 2>/dev/null && return 0
  # Se nao e pagina de login, assume activa
  ! grep -q 'loginForm\|showSigninLink' "$f" 2>/dev/null
}

check_session_alive() {
  fetch_page "/angar"
  if ! _session_active; then
    log "sessao expirou — a reconectar" "WARN"
    _do_login 2>/dev/null || true
    fetch_page "/angar"
  fi
}

require_login() {
  _session_active && return 0
  _LOGIN_FAILURES=$(( _LOGIN_FAILURES + 1 ))
  [ "$_LOGIN_FAILURES" -ge 3 ] && { log_error "3 falhas login"; return 1; }
  [ -f "$CRIPT_FILE" ] && { JSESSIONID=""; _do_login; sleep_rand 1000 2000; }
  fetch_page "/angar"
  _session_active
}
