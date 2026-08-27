#!/bin/bash
# cw.sh — Guerra (Clan War) v2.2.0
#
# LOGICA SIMPLIFICADA:
#   Todos os disparos com intervalo FIXO de 6 segundos.
#   Sem logica de manobra — no CW nao ha manobras de inimigos a gerir.
#   Repair a 50% HP, tenta de 5 em 5s.
#   Manobra propria usa quando recebe dano.

cw_check_and_apply() {
  [ "$FUNC_cw" = "n" ] && return 0

  fetch_page "/cw"
  if ! _session_active; then return; fi

  if grep -q 'currentControl-buttons-attackRegularShellLink' "$SRC" 2>/dev/null; then
    echo "[cw] batalha activa"
    _cw_fight
    return
  fi

  local enter_link
  enter_link=$(grep -o -E \
    'cw\?[0-9]+-[0-9]+\.ILinkListener-currentOverview-apply' \
    "$SRC" | head -n1)

  if [ -n "$enter_link" ]; then
    local war_country war_start
    war_country=$(grep -o -E 'class="green1">[^<]+' "$SRC" \
      | sed 's/.*">//' | head -n1)
    war_start=$(grep -o -E 'Start in [0-9]{2}:[0-9]{2}:[0-9]{2}' "$SRC" | head -n1)
    echo "[cw] a entrar: ${war_country:-?} ${war_start}"
    fetch_page "$enter_link"
    sleep_rand 500 1000
    _cw_wait_start
  else
    local tokens war_country
    tokens=$(grep -o -E 'My tokens:[^0-9]*[0-9]+' "$SRC" \
      | grep -o -E '[0-9]+' | head -n1)
    war_country=$(grep -o -E 'class="green1">[^<]+' "$SRC" \
      | sed 's/.*">//' | head -n1)
    echo "[cw] ${war_country:-sem guerra} | tokens: ${tokens:-0}"
  fi
}

cw_mode() {
  [ "$FUNC_cw" = "n" ] && return 0
  cw_check_and_apply
}

_cw_wait_start() {
  local timeout=$(( $(date +%s) + 60 ))
  echo "[cw] a aguardar inicio..."
  while [ "$(date +%s)" -lt "$timeout" ]; do
    grep -q 'currentControl-buttons-attackRegularShellLink' "$SRC" 2>/dev/null && {
      echo "[cw] batalha iniciada"
      _cw_fight
      return
    }
    local ref
    ref=$(grep -o -E \
      'cw\?[0-9]+-[0-9]+\.ILinkListener-[^"]*refresh[^"]*' \
      "$SRC" | head -n1)
    [ -n "$ref" ] && fetch_page "$ref" || fetch_page "/cw"
    sleep_rand 2000 3000
  done
  echo "[cw] timeout"
}

_cw_fight() {
  local timeout=$(( $(date +%s) + 600 ))
  local shots=0
  local hp_max=""
  local last_repair_attempt=0
  local repair_retry=5

  # HP inicial
  hp_max=$(grep -o -E \
    'value-block lh1[^>]*>[^<]*<[^>]*>[^<]*>[0-9]+' "$SRC" \
    | grep -o -E '[0-9]+$' | sed -n '1p')
  echo "[cw] inicio | HP: ${hp_max:-?}"

  while [ "$(date +%s)" -lt "$timeout" ]; do
    _session_active || { echo "[cw] sessao perdida"; break; }

    # Extrai links
    local atk repair maneuver escape
    atk=$(grep -o -E \
      'cw\?[0-9]+-[0-9]+\.ILinkListener-currentControl-buttons-attackRegularShellLink' \
      "$SRC" | head -n1)
    repair=$(grep -o -E \
      'cw\?[0-9]+-[0-9]+\.ILinkListener-currentControl-buttons-repairLink' \
      "$SRC" | head -n1)
    maneuver=$(grep -o -E \
      'cw\?[0-9]+-[0-9]+\.ILinkListener-currentControl-buttons-maneuverLink' \
      "$SRC" | head -n1)
    escape=$(grep -o -E \
      'cw\?[0-9]+-[0-9]+\.ILinkListener-currentControl-escape' \
      "$SRC" | head -n1)

    # Fim da batalha
    [ -z "$atk" ] && [ -z "$escape" ] && {
      echo "[cw] batalha terminou ($shots disparos)"
      break
    }

    # HP actual
    local hp_now hp_enemy
    hp_now=$(grep -o -E \
      'value-block lh1[^>]*>[^<]*<[^>]*>[^<]*>[0-9]+' "$SRC" \
      | grep -o -E '[0-9]+$' | sed -n '1p')
    hp_enemy=$(grep -o -E \
      'value-block lh1[^>]*>[^<]*<[^>]*>[^<]*>[0-9]+' "$SRC" \
      | grep -o -E '[0-9]+$' | sed -n '2p')
    [ -z "$hp_max" ] && [ -n "$hp_now" ] && hp_max="$hp_now"

    local now=$(date +%s)
    local since_repair=$(( now - last_repair_attempt ))

    # HP percentagem
    local hp_pct=""
    [ -n "$hp_now" ] && [ "${hp_max:-0}" -gt 0 ] && \
      hp_pct=$(awk -v n="$hp_now" -v m="$hp_max" \
        'BEGIN{printf"%.0f",n/m*100}' 2>/dev/null)

    # ── REPAIR: tenta de 5 em 5s se HP < 50% ─────────────────
    if [ "${hp_pct:-100}" -le 50 ] && \
       [ "$since_repair" -ge "$repair_retry" ] 2>/dev/null; then
      last_repair_attempt=$now
      if [ -n "$repair" ]; then
        echo "[cw] REPAIR HP: $hp_now (${hp_pct}%)"
        fetch_page_fast "$repair"
        continue
      else
        echo "[cw] repair indisponivel — tenta em ${repair_retry}s"
      fi
    fi

    # ── MANOBRA propria: usa quando recebe dano ───────────────
    if [ -n "$maneuver" ] 2>/dev/null; then
      if grep -q 'causou-lhe danos' "$SRC" 2>/dev/null; then
        echo "[cw] manobra"
        fetch_page_fast "$maneuver"
        continue
      fi
    fi

    # ── DISPARO: intervalo FIXO de 6 segundos ─────────────────
    [ -z "$atk" ] && { sleep 1s; continue; }

    # Espera 6s completos antes de disparar
    sleep 6s

    fetch_page_fast "$atk"
    shots=$(( shots + 1 ))
    echo "[cw] #${shots} | HP: ${hp_now:-?} (${hp_pct:-?}%) vs ${hp_enemy:-?}"

  done

  echo "[cw] fim: $shots disparos"
  go_hangar
}
