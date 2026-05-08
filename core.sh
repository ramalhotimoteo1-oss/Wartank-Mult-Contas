#!/bin/bash
# core.sh — Funções base v1.0.0 (multi-conta)

URL="${URL:-https://wartank-pt.net}"
USER_AGENT="Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

# Paths por conta — definidos pelo controlador antes de source
# TMP, COOKIE_FILE, CRIPT_FILE, LOG_FILE, SRC já estão exportados

_LOGIN_FAILURES=0
JSESSIONID=""
ACC=""
FUEL_CURRENT=""
PLAYER_LEVEL=""
PLAYER_ID=""

# ── Cores ────────────────────────────────────────────────────
GOLD='\033[0;33m'
GREEN='\033[32m'
RED='\033[0;31m'
GRAY='\033[02;37m'
RESET='\033[00m'

# ── Log ──────────────────────────────────────────────────────
log() {
  local ts
  printf -v ts '%(%Y-%m-%d %H:%M:%S)T' -1
  echo "[$ts] [${2:-INFO}] $1" >> "$LOG_FILE"
}
log_warn()  { log "$1" "WARN";  echo "[${ACC:-?}] [AVISO] $1"; }
log_error() { log "$1" "ERROR"; echo "[${ACC:-?}] [ERRO]  $1"; }
log_ok()    { log "$1" "OK";    echo "[${ACC:-?}] [OK]    $1"; }

# ── Delay aleatório ──────────────────────────────────────────
sleep_rand() {
  local min="${1:-300}" max="${2:-1200}" delay
  delay=$(awk -v min="$min" -v max="$max" \
    'BEGIN { srand(); printf "%.3f", (min + rand()*(max-min))/1000 }')
  sleep "${delay}s"
}

# ── Credenciais ──────────────────────────────────────────────
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

# ── JSESSIONID ───────────────────────────────────────────────
_update_jsessionid() {
  local s
  s=$(grep -o -E 'jsessionid=[A-Z0-9]+' "$SRC" 2>/dev/null | head -n1 | sed 's/jsessionid=//')
  [ -n "$s" ] && JSESSIONID="$s"
}

# ── Fetch normal (com delay) ─────────────────────────────────
fetch_page() {
  local path="$1"
  local output="${2:-$SRC}"
  local full_url

  path=$(echo "$path" | sed 's/;jsessionid=[A-Z0-9]*//')

  if [ -n "$JSESSIONID" ]; then
    if echo "$path" | grep -q '?'; then
      full_url="${URL}/$(echo "$path" | sed "s|?|;jsessionid=${JSESSIONID}?|")"
    else
      full_url="${URL}/${path};jsessionid=${JSESSIONID}"
    fi
  else
    full_url="${URL}/${path}"
  fi

  full_url=$(echo "$full_url" | sed 's|https://||;s|//|/|g;s|^|https://|')

  local cacert=""
  for ca in \
    /data/data/com.termux/files/usr/etc/tls/cert.pem \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt; do
    [ -f "$ca" ] && { cacert="--cacert $ca"; break; }
  done

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    -A "$USER_AGENT" \
    --max-time 20 \
    --retry 2 \
    --retry-delay 3 \
    $cacert \
    -o "$output" \
    "$full_url" \
    2>>"$LOG_FILE"

  [ ! -s "$output" ] && log "fetch vazio: $path" "WARN"
  _update_jsessionid
  sleep_rand 300 700
}

# ── Fetch rápido (sem delay — para combate) ──────────────────
fetch_page_fast() {
  local path="$1"
  local output="${2:-$SRC}"
  local full_url

  path=$(echo "$path" | sed 's/;jsessionid=[A-Z0-9]*//')

  if [ -n "$JSESSIONID" ]; then
    if echo "$path" | grep -q '?'; then
      full_url="${URL}/$(echo "$path" | sed "s|?|;jsessionid=${JSESSIONID}?|")"
    else
      full_url="${URL}/${path};jsessionid=${JSESSIONID}"
    fi
  else
    full_url="${URL}/${path}"
  fi

  full_url=$(echo "$full_url" | sed 's|https://||;s|//|/|g;s|^|https://|')

  local cacert=""
  for ca in \
    /data/data/com.termux/files/usr/etc/tls/cert.pem \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt; do
    [ -f "$ca" ] && { cacert="--cacert $ca"; break; }
  done

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" \
    -b "$COOKIE_FILE" \
    -A "$USER_AGENT" \
    --max-time 20 \
    --retry 1 \
    $cacert \
    -o "$output" \
    "$full_url" \
    2>>"$LOG_FILE"

  [ ! -s "$output" ] && log "fetch_fast vazio: $path" "WARN"
  _update_jsessionid
}

# ── Sessão ───────────────────────────────────────────────────
_session_active() {
  local f="${1:-$SRC}"
  grep -q 'user=0;level=0' "$f" 2>/dev/null && return 1
  grep -q 'IFormSubmitListener-loginForm\|showSigninLink' "$f" 2>/dev/null && return 1
  return 0
}

check_session_alive() {
  fetch_page "/angar"
  if ! _session_active; then
    log "sessao expirou — a reconectar" "WARN"
    _do_login
    fetch_page "/angar"
  fi
}
