#!/bin/bash
# assault.sh — Missao Especial v5.1.0
#
# ALTERACOES v5.1.0:
#   + Cooldown de 20h APOS destruicao/fim do combate (persistente em $TMP)
#   + Durante o cooldown: NAO tenta join de novo
#   + Ainda processa combate/lobby/contagem se ja estiver a meio
#   + Sem joinLink no jogo → marca cooldown (evita spam)
#
# Fixes v5.0.0 mantidos:
#   + HP via rate-block, repair 20%, miss counter, paths /company/

ASSAULT_COOLDOWN_SEC="${ASSAULT_COOLDOWN_SEC:-72000}"  # 20 horas
ASSAULT_TS_FILE="${TMP}/last_assault_ts"

# Grava timestamp do fim (destruicao / sem missao)
_assault_mark_done() {
  mkdir -p "$TMP" 2>/dev/null
  date +%s > "$ASSAULT_TS_FILE"
  echo "[assault] cooldown 20h iniciado ($(date '+%H:%M' 2>/dev/null || echo now))"
}

# Segundos em falta no cooldown (0 = pode tentar join)
_assault_cooldown_left() {
  [ -f "$ASSAULT_TS_FILE" ] || { echo 0; return; }
  local last now left
  last=$(cat "$ASSAULT_TS_FILE" 2>/dev/null)
  [ -z "$last" ] && { echo 0; return; }
  now=$(date +%s)
  left=$(( ASSAULT_COOLDOWN_SEC - (now - last) ))
  [ "$left" -lt 0 ] && left=0
  echo "$left"
}

assault_mode() {
  [ "$FUNC_assault" = "n" ] && return 0

  local left
  left=$(_assault_cooldown_left)

  echo "[assault] verificar"

  fetch_page "/company/assault"
  if ! _session_active; then return; fi

  # Estado 1: combate activo — sempre processa (mesmo em cooldown)
  if grep -q 'control-buttons-attackRegularShellLink' "$SRC" 2>/dev/null; then
    echo "[assault] estado: combate"
    _assault_fight
    return
  fi

  # Estado 2: contagem regressiva
  if grep -q 'control-banner-refresh' "$SRC" 2>/dev/null; then
    echo "[assault] estado: contagem"
    _assault_wait_countdown
    return
  fi

  # Estado 3: lobby
  if grep -q 'overview-startBattleLink\|overview-refreshLink\|overview-unapplyLink' \
     "$SRC" 2>/dev/null; then
    echo "[assault] estado: lobby"
    _assault_lobby
    return
  fi

  # Em cooldown local: nao tenta entrar de novo
  if [ "$left" -gt 0 ] 2>/dev/null; then
    local hrs=$(( left / 3600 ))
    local mins=$(( (left % 3600) / 60 ))
    echo "[assault] cooldown — falta ~${hrs}h${mins}m"
    return
  fi

  # Estado 4: lista de missoes — so fora do cooldown
  if grep -q 'allAssaults-assaults\|joinLink' "$SRC" 2>/dev/null; then
    _assault_join
    return
  fi

  # Sem missao / sem join → jogo em CD; grava para nao spammar
  echo "[assault] sem missao disponivel"
  _assault_mark_done
}

# ── Join: entra no Abrigo (Blindage.png) ──────────────────────
_assault_join() {
  local join_link

  join_link=$(grep -B1 'Blindage' "$SRC" 2>/dev/null \
    | grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-allAssaults-assaults-[0-9]+-joinLink' \
    | head -n1)

  [ -z "$join_link" ] && \
    join_link=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-allAssaults-assaults-[0-9]+-joinLink' \
      "$SRC" | tail -n1)

  if [ -z "$join_link" ]; then
    echo "[assault] sem joinLink — cooldown no jogo"
    _assault_mark_done
    return
  fi

  echo "[assault] a entrar: $join_link"
  fetch_page "/company/$join_link"
  sleep_rand 1000 1500

  local tries=0
  while [ "$tries" -lt 5 ]; do
    if grep -q 'control-buttons-attackRegularShellLink' "$SRC" 2>/dev/null; then
      echo "[assault] estado: combate"; _assault_fight; return
    elif grep -q 'control-banner-refresh' "$SRC" 2>/dev/null; then
      echo "[assault] estado: contagem"; _assault_wait_countdown; return
    elif grep -q 'overview-startBattleLink\|overview-refreshLink\|overview-unapplyLink' \
         "$SRC" 2>/dev/null; then
      echo "[assault] estado: lobby"; _assault_lobby; return
    fi
    tries=$(( tries + 1 ))
    echo "[assault] aguarda ($tries/5)"
    sleep 3s
    fetch_page "/company/assault"
  done
  echo "[assault] estado desconhecido apos join"
}

_assault_lobby() {
  local min_members="${ASSAULT_MIN_MEMBERS:-1}"
  local timeout=$(( $(date +%s) + 180 ))
  echo "[assault] lobby — min membros: $min_members"

  while [ "$(date +%s)" -lt "$timeout" ]; do
    local objective members current_members start_link ref

    objective=$(grep -o -E 'Objetivo: [^<]+' "$SRC" | sed 's/Objetivo: //' | head -n1)
    members=$(grep -o -E 'Tanquistas: [0-9]+ de [0-9]+' "$SRC" | head -n1)
    current_members=$(echo "$members" | grep -o -E '[0-9]+' | head -n1)
    start_link=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-overview-startBattleLink' \
      "$SRC" | head -n1)

    echo "[assault] ${objective:-?} | ${members:-?}"

    if [ -n "$current_members" ] && \
       [ "$current_members" -ge "$min_members" ] 2>/dev/null; then
      if [ -n "$start_link" ]; then
        echo "[assault] $current_members membros — a iniciar"
        fetch_page "/company/$start_link"
        sleep_rand 1000 2000
        if grep -q 'control-buttons-attackRegularShellLink' "$SRC" 2>/dev/null; then
          _assault_fight
        elif grep -q 'control-banner-refresh' "$SRC" 2>/dev/null; then
          _assault_wait_countdown
        fi
        return
      fi
    else
      echo "[assault] aguarda membros (${current_members:-0}/$min_members)"
    fi

    ref=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-overview-refreshLink' \
      "$SRC" | head -n1)
    [ -n "$ref" ] && fetch_page "/company/$ref"
    sleep 15s
  done

  echo "[assault] timeout lobby — a rejeitar"
  local unapply
  unapply=$(grep -o -E \
    'assault\?[0-9]+-[0-9]+\.ILinkListener-overview-unapplyLink' \
    "$SRC" | head -n1)
  [ -n "$unapply" ] && fetch_page "/company/$unapply"
}

_assault_wait_countdown() {
  local timeout=$(( $(date +%s) + 60 ))
  echo "[assault] contagem regressiva..."
  while [ "$(date +%s)" -lt "$timeout" ]; do
    if grep -q 'control-buttons-attackRegularShellLink' "$SRC" 2>/dev/null; then
      echo "[assault] combate iniciado"
      _assault_fight
      return
    fi
    local countdown
    countdown=$(grep -o -E 'ficam [0-9]+ segundo' "$SRC" \
      | grep -o -E '[0-9]+' | head -n1)
    echo "[assault] ${countdown:-?}s..."
    local ref
    ref=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-control-banner-refresh' \
      "$SRC" | head -n1)
    [ -n "$ref" ] && fetch_page "/company/$ref" || fetch_page "/company/assault"
    sleep 3s
  done
  echo "[assault] timeout na contagem"
}

_assault_get_hp() {
  local hp
  hp=$(grep -A5 'rate-block' "$SRC" 2>/dev/null \
    | grep -o -E '<span><span>[0-9]+' \
    | grep -o -E '[0-9]+' | tail -n1)

  [ -z "$hp" ] && \
    hp=$(grep -o -E '<span><span>[0-9]+</span>' "$SRC" \
      | grep -o -E '[0-9]+' \
      | awk '$1+0 > 100' | head -n1)

  echo "$hp"
}

_assault_fight() {
  local shots=0
  local timeout=$(( $(date +%s) + 600 ))
  local hp_max=""
  local last_repair=0
  local repair_retry=5
  local repair_threshold=20
  local miss=0

  hp_max=$(_assault_get_hp)
  echo "[assault] combate | HP max: ${hp_max:-?}"

  while [ "$(date +%s)" -lt "$timeout" ]; do
    _session_active || { echo "[assault] sessao perdida"; break; }

    local atk repair
    atk=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-control-buttons-attackRegularShellLink' \
      "$SRC" | head -n1)
    repair=$(grep -o -E \
      'assault\?[0-9]+-[0-9]+\.ILinkListener-control-buttons-repairLink' \
      "$SRC" | head -n1)

    if [ -z "$atk" ]; then
      miss=$(( miss + 1 ))
      if [ "$miss" -ge 3 ]; then
        echo "[assault] sem link de ataque (3x) — fim"
        break
      fi
      echo "[assault] sem atk ($miss/3) — a recarregar"
      sleep 3s
      fetch_page "/company/assault"
      continue
    fi
    miss=0

    local hp_now
    hp_now=$(_assault_get_hp)
    [ -z "$hp_max" ] && [ -n "$hp_now" ] && hp_max="$hp_now"

    local now=$(date +%s)
    local since_repair=$(( now - last_repair ))
    local hp_pct=""

    if [ -n "$hp_now" ] && [ "${hp_max:-0}" -gt 0 ] 2>/dev/null; then
      hp_pct=$(awk -v n="$hp_now" -v m="$hp_max" \
        'BEGIN{printf"%.0f",n/m*100}' 2>/dev/null)
    else
      echo "[assault] AVISO: HP nao detectado"
    fi

    if [ -n "$hp_pct" ] && \
       [ "$hp_pct" -le "$repair_threshold" ] && \
       [ "$since_repair" -ge "$repair_retry" ] 2>/dev/null; then
      last_repair=$now
      if [ -n "$repair" ]; then
        echo "[assault] REPAIR HP: $hp_now (${hp_pct}%)"
        fetch_page_fast "/company/$repair"; continue
      else
        echo "[assault] repair indisponivel"
      fi
    fi

    sleep 6s
    fetch_page_fast "/company/$atk"
    shots=$(( shots + 1 ))
    echo "[assault] #${shots} | HP: ${hp_now:-?} (${hp_pct:-?}%)"
  done

  echo "[assault] fim: $shots disparos"
  # Destruicao / fim → 20h ate a proxima tentativa de join
  _assault_mark_done
  go_hangar
}
