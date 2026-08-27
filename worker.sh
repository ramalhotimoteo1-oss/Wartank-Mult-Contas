#!/bin/bash
# worker.sh — Motor multi-conta LEVE v2.1.0
#
# Foco: XP, missoes, recursos da base, PvP
# Modulos:
#   cw | assault | pvp | convoy | battle | base | missions
#
# Chamado pelo controller com:
#   ACC, TMP, COOKIE_FILE, CRIPT_FILE, LOG_FILE, SRC, STATUS_FILE

BOT_DIR="$(cd "$(dirname "$0")" && pwd)"

for cmd in bash curl grep sed awk base64; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERRO FATAL: '$cmd' nao encontrado"
    exit 1
  }
done

_load() {
  local f="$BOT_DIR/$1"
  [ -f "$f" ] || { echo "ERRO FATAL: modulo '$1' nao encontrado"; exit 1; }
  # shellcheck source=/dev/null
  . "$f" || { echo "ERRO FATAL: falha ao carregar '$1'"; exit 1; }
}

_load core.sh
_load status.sh
_load login.sh
_load combat_common.sh 2>/dev/null || true
_load battle.sh
_load missions.sh
_load base.sh
_load pvp.sh
_load cw.sh
_load convoy.sh
_load assault.sh

mkdir -p "$TMP"

BATTLE_LA="${BATTLE_LA:-3}"
BATTLE_SHOTS="${BATTLE_SHOTS:-9}"
BATTLE_TIMEOUT="${BATTLE_TIMEOUT:-600}"
BATTLE_WINDOW="${BATTLE_WINDOW:-3}"
ASSAULT_COOLDOWN_SEC="${ASSAULT_COOLDOWN_SEC:-72000}"
FUNC_battle="${FUNC_battle:-y}"
FUNC_missions="${FUNC_missions:-y}"
FUNC_buildings="${FUNC_buildings:-y}"
FUNC_pvp="${FUNC_pvp:-y}"
FUNC_cw="${FUNC_cw:-y}"
FUNC_convoy="${FUNC_convoy:-y}"
FUNC_assault="${FUNC_assault:-y}"
FUNC_market_gold="${FUNC_market_gold:-n}"

LAST_BATTLE_SLOT=""

_battle_current_slot() {
  local h m total slot_min slot_h slot_m diff
  printf -v h '%(%H)T' -1
  printf -v m '%(%M)T' -1
  h=$((10#$h)); m=$((10#$m))
  total=$(( h * 60 + m ))
  slot_min=$(( (total / 40) * 40 ))
  diff=$(( total - slot_min ))
  [ "$diff" -ge "${BATTLE_WINDOW:-3}" ] && { echo ""; return; }
  slot_h=$(( slot_min / 60 ))
  slot_m=$(( slot_min % 60 ))
  printf '%02d:%02d' "$slot_h" "$slot_m"
}

_can_battle() {
  [ "$FUNC_battle" = "n" ] && return 1
  local slot
  slot=$(_battle_current_slot)
  [ -z "$slot" ] && return 1
  [ "$LAST_BATTLE_SLOT" = "$slot" ] && return 1
  local fuel="${FUEL_CURRENT:-0}"
  [ -z "$fuel" ] || [ "$fuel" -lt 90 ] 2>/dev/null && return 1
  return 0
}

_status_write "login" 2>/dev/null || true

if ! login_func; then
  _status_write "erro_login" 2>/dev/null || true
  echo "[${ACC}] ERRO: login falhou — worker a terminar"
  exit 1
fi

echo "[${ACC}] worker LEVE activo (xp/missoes/base/pvp)"

while true; do
  fetch_page "/angar"
  if ! _session_active; then
    log "sessao expirada — a reconectar" "WARN"
    _status_write "reconectar" 2>/dev/null || true
    _do_login
    fetch_page "/angar"
  fi

  FUEL_CURRENT=$(grep -o -E 'fuel\.png[^/]*/>[^0-9]*[0-9]+' "$SRC" 2>/dev/null \
    | grep -o -E '[0-9]+$' | head -n1)
  [ -z "$FUEL_CURRENT" ] && \
    FUEL_CURRENT=$(grep -A1 'title="Combustível"' "$SRC" 2>/dev/null \
      | grep -o -E '[0-9]+' | head -n1)
  PLAYER_LEVEL=$(grep -o -E 'level=[0-9]+' "$SRC" 2>/dev/null \
    | grep -o -E '[0-9]+' | head -n1)

  _status_write "online" 2>/dev/null || true

  # 1. CW se activo
  if [ "$FUNC_cw" = "y" ]; then
    fetch_page "/cw"
    if _session_active && grep -qE \
      'attackRegularShellLink|currentOverview-apply' "$SRC" 2>/dev/null; then
      _status_write "battle" 2>/dev/null || true
      cw_check_and_apply 2>/dev/null || true
    fi
  fi

  # 2. PvP — horarios 05:23 / 11:23 / 21:23 (interno ao pvp.sh)
  if [ "$FUNC_pvp" = "y" ]; then
    _status_write "pvp" 2>/dev/null || true
    pvp_mode 2>/dev/null || true
  fi

  # 3. Adiante a combate — slots de 40 min
  if _can_battle; then
    _status_write "battle" 2>/dev/null || true
    adiante_a_combate
    LAST_BATTLE_SLOT=$(_battle_current_slot)
  fi

  # 4. Missoes
  if [ "$FUNC_missions" = "y" ]; then
    collect_all_rewards 2>/dev/null || missions_func 2>/dev/null || true
  fi

  # 5. Base
  if [ "$FUNC_buildings" = "y" ]; then
    base_mode 2>/dev/null || true
  fi

  # 6. Escolta
  if [ "$FUNC_convoy" = "y" ]; then
    convoy_mode 2>/dev/null || true
  fi

  # 7. Assault (cooldown 20h)
  if [ "$FUNC_assault" = "y" ]; then
    assault_mode 2>/dev/null || true
  fi

  _status_write "online" 2>/dev/null || true
  sleep_rand 40000 70000
done
