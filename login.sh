#!/bin/bash
# login.sh — Login v1.0.0 (multi-conta)
# Lê credenciais já encriptadas em CRIPT_FILE
# O controlador (controller.sh) popula o CRIPT_FILE antes de iniciar o worker

login_func() {
  if [ ! -f "$CRIPT_FILE" ] || [ ! -s "$CRIPT_FILE" ]; then
    log_error "CRIPT_FILE ausente: $CRIPT_FILE"
    return 1
  fi

  log "A fazer login: $ACC" "INFO"
  _do_login

  if ! _check_session; then
    log_error "Login falhou para $ACC"
    rm -f "$COOKIE_FILE"
    return 1
  fi

  log_ok "Login OK: $ACC | nivel:${PLAYER_LEVEL:-?} | combustivel:${FUEL_CURRENT:-?}"
  _status_write "online"
  return 0
}

_do_login() {
  local creds user pass

  creds=$(_decrypt_creds "$CRIPT_FILE")
  if [ -z "$creds" ]; then
    log_error "Nao conseguiu ler credenciais"
    return 1
  fi

  user=$(echo "$creds" | sed 's/login=\([^&]*\).*/\1/')
  pass=$(echo "$creds" | sed 's/.*password=\(.*\)/\1/')
  ACC="${ACC:-$user}"

  # Passo 1: página inicial
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 \
    -o "$SRC" "${URL}/" 2>>"$LOG_FILE"
  sleep_rand 400 800

  # Passo 2: link de signin
  local signin_link
  signin_link=$(grep -o -E '\?[0-9]+-[0-9]+\.ILinkListener-showSigninLink' \
    "$SRC" | head -n1)

  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 \
    -o "$SRC" "${URL}/${signin_link}" 2>>"$LOG_FILE"
  sleep_rand 400 800

  # Passo 3: form action
  local form_action
  form_action=$(grep -o -E '\?[0-9]+-[0-9]+\.IFormSubmitListener-loginForm' \
    "$SRC" | head -n1)

  if [ -z "$form_action" ]; then
    _update_jsessionid
    log "form nao encontrado" "WARN"
    return 0
  fi

  # Passo 4: POST
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 \
    -X POST \
    --data-urlencode "login=${user}" \
    --data-urlencode "password=${pass}" \
    --data-urlencode "id1_hf_0=" \
    -o "$SRC" \
    "${URL}/${form_action}" 2>>"$LOG_FILE"

  unset user pass creds
  sleep_rand 800 1500
  _update_jsessionid
}

_check_session() {
  local tmp_file="$TMP/session_check"
  local cacert=""
  for ca in \
    /data/data/com.termux/files/usr/etc/tls/cert.pem \
    /etc/ssl/certs/ca-certificates.crt; do
    [ -f "$ca" ] && { cacert="--cacert $ca"; break; }
  done

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 \
    $cacert \
    -o "$tmp_file" \
    "${URL}/angar;jsessionid=${JSESSIONID}" 2>>"$LOG_FILE"

  if grep -q '<title>Hangar</title>' "$tmp_file" 2>/dev/null; then
    PLAYER_ID=$(grep -o -E 'user=[0-9]+' "$tmp_file" \
      | grep -o -E '[0-9]+' | head -n1)
    PLAYER_LEVEL=$(grep -o -E 'level=[0-9]+' "$tmp_file" \
      | grep -o -E '[0-9]+' | head -n1)
    FUEL_CURRENT=$(grep -A1 'title="Combustível"' "$tmp_file" \
      | grep -o -E '[0-9]+' | head -n1)
    [ -z "$ACC" ] && ACC="ID:${PLAYER_ID:-?}"
    cp "$tmp_file" "$SRC"
    _update_jsessionid
    return 0
  fi

  return 1
}
