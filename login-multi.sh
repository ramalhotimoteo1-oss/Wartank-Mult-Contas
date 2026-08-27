#!/bin/bash
# login.sh — Login v2.0.0 (multi-conta)
#
# Sem prompt interactivo: credenciais vem do controller (CRIPT_FILE por conta).
# Tenta cookies primeiro; se falharem, POST de login.
# Nao apaga CRIPT_FILE em falha de rede.

login_func() {
  if [ ! -f "$CRIPT_FILE" ] || [ ! -s "$CRIPT_FILE" ]; then
    log_error "CRIPT_FILE ausente: $CRIPT_FILE"
    return 1
  fi

  # Nome da conta a partir do ficheiro
  local creds user
  creds=$(_decrypt_creds "$CRIPT_FILE")
  user=$(echo "$creds" | sed 's/login=\([^&]*\).*/\1/')
  [ -n "$user" ] && ACC="${ACC:-$user}"
  unset creds user

  echo "[${ACC}] a autenticar..."

  # 1) Cookies ainda validos?
  if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
    if _check_session; then
      log_ok "Sessao recuperada: $ACC | nv:${PLAYER_LEVEL:-?} | fuel:${FUEL_CURRENT:-?}"
      _status_write "online" 2>/dev/null || true
      return 0
    fi
  fi

  # 2) Login completo
  if ! _do_login; then
    log_error "Login POST falhou: $ACC"
    return 1
  fi

  if ! _check_session; then
    log_error "Login falhou: $ACC (credenciais ou rede)"
    rm -f "$COOKIE_FILE"
    return 1
  fi

  log_ok "Login OK: $ACC | nv:${PLAYER_LEVEL:-?} | fuel:${FUEL_CURRENT:-?} | id:${PLAYER_ID:-?}"
  _status_write "online" 2>/dev/null || true
  return 0
}

_do_login() {
  local creds user pass cacert
  creds=$(_decrypt_creds "$CRIPT_FILE")
  if [ -z "$creds" ]; then
    log_error "Nao conseguiu ler credenciais"
    return 1
  fi

  user=$(echo "$creds" | sed 's/login=\([^&]*\).*/\1/')
  pass=$(echo "$creds" | sed 's/.*password=\(.*\)/\1/')
  ACC="${ACC:-$user}"
  cacert=$(_cacert_arg 2>/dev/null || true)

  # Passo 1: home
  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 25 --retry 2 \
    $cacert \
    -o "$SRC" "${URL}/" 2>>"$LOG_FILE"
  sleep_rand 400 800

  # Passo 2: signin link
  local signin_link
  signin_link=$(grep -o -E '\?[0-9]+-[0-9]+\.ILinkListener-showSigninLink' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -n "$signin_link" ]; then
    # shellcheck disable=SC2086
    curl -s -L \
      -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
      -A "$USER_AGENT" --max-time 25 \
      $cacert \
      -o "$SRC" "${URL}/${signin_link}" 2>>"$LOG_FILE"
    sleep_rand 400 800
  fi

  # Passo 3: form
  local form_action
  form_action=$(grep -o -E '\?[0-9]+-[0-9]+\.IFormSubmitListener-loginForm' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$form_action" ]; then
    _update_jsessionid
    if grep -q '<title>Hangar</title>\|user=[1-9]' "$SRC" 2>/dev/null; then
      unset user pass creds
      return 0
    fi
    log "form de login nao encontrado" "WARN"
    unset user pass creds
    return 1
  fi

  # Passo 4: POST
  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 25 \
    $cacert \
    -X POST \
    --data-urlencode "login=${user}" \
    --data-urlencode "password=${pass}" \
    --data-urlencode "id1_hf_0=" \
    -o "$SRC" \
    "${URL}/${form_action}" 2>>"$LOG_FILE"

  unset user pass creds
  sleep_rand 800 1500
  _update_jsessionid
  return 0
}

_check_session() {
  local tmp_file="$TMP/session_check"
  local cacert angar_url
  cacert=$(_cacert_arg 2>/dev/null || true)
  angar_url="${URL}/angar"
  [ -n "$JSESSIONID" ] && angar_url="${URL}/angar;jsessionid=${JSESSIONID}"

  # shellcheck disable=SC2086
  curl -s -L \
    -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -A "$USER_AGENT" --max-time 20 \
    $cacert \
    -o "$tmp_file" \
    "$angar_url" 2>>"$LOG_FILE"

  if grep -q '<title>Hangar</title>' "$tmp_file" 2>/dev/null && \
     ! grep -q 'user=0;level=0\|showSigninLink\|loginForm' "$tmp_file" 2>/dev/null; then
    PLAYER_ID=$(grep -o -E 'user=[0-9]+' "$tmp_file" \
      | grep -o -E '[0-9]+' | head -n1)
    PLAYER_LEVEL=$(grep -o -E 'level=[0-9]+' "$tmp_file" \
      | grep -o -E '[0-9]+' | head -n1)
    FUEL_CURRENT=$(grep -A1 'title="Combustível"' "$tmp_file" 2>/dev/null \
      | grep -o -E '[0-9]+' | head -n1)
    [ -z "$FUEL_CURRENT" ] && \
      FUEL_CURRENT=$(grep -o -E 'fuel\.png[^0-9]*[0-9]+' "$tmp_file" 2>/dev/null \
        | grep -o -E '[0-9]+$' | head -n1)
    cp "$tmp_file" "$SRC" 2>/dev/null
    _update_jsessionid
    return 0
  fi
  return 1
}
