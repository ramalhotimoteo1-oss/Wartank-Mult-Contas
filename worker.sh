#!/bin/bash
# worker.sh — Motor por conta v1.0.0
# Chamado pelo controlador com variáveis já exportadas:
#   ACC, TMP, COOKIE_FILE, CRIPT_FILE, LOG_FILE, SRC, STATUS_FILE

BOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Verifica dependências
for cmd in bash curl grep sed awk base64; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERRO FATAL: '$cmd' nao encontrado"
    exit 1
  }
done

# Carrega módulos
_load() {
  local f="$BOT_DIR/$1"
  [ -f "$f" ] || { echo "ERRO FATAL: modulo '$1' nao encontrado"; exit 1; }
  # shellcheck source=/dev/null
  . "$f" || { echo "ERRO FATAL: falha ao carregar '$1'"; exit 1; }
}

_load core.sh
_load status.sh
_load login.sh
_load battle.sh
_load pvp.sh

mkdir -p "$TMP"

# ── Config de batalha ────────────────────────────────────────
BATTLE_LA="${BATTLE_LA:-3}"
BATTLE_SHOTS="${BATTLE_SHOTS:-9}"
BATTLE_TIMEOUT="${BATTLE_TIMEOUT:-600}"

# ── Login inicial ────────────────────────────────────────────
_status_write "login"

if ! login_func; then
  _status_write "erro_login"
  echo "[${ACC}] ERRO: login falhou — worker a terminar"
  exit 1
fi

# ── Loop principal ───────────────────────────────────────────
echo "[${ACC}] worker activo"

while true; do
  # Verifica sessão
  fetch_page "/angar"
  if ! _session_active; then
    log "sessao expirada — a reconectar" "WARN"
    _status_write "reconectar"
    _do_login
    fetch_page "/angar"
  fi

  # Actualiza dados do hangar
  FUEL_CURRENT=$(grep -o -E 'fuel\.png[^/]*/>[^0-9]*[0-9]+' "$SRC" \
    | grep -o -E '[0-9]+$' | head -n1)
  PLAYER_LEVEL=$(grep -o -E 'level=[0-9]+' "$SRC" \
    | grep -o -E '[0-9]+' | head -n1)

  _status_write "online"

  # 1. PVP — verifica horário
  pvp_mode

  # 2. Adiante a Combate
  adiante_a_combate

  # Pausa entre ciclos (30s a 60s)
  sleep_rand 30000 60000
done
