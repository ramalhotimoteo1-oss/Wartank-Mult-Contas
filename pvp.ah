#!/bin/bash
# pvp.sh — PvP v2.0.0
#
# HORARIOS FIXOS: 05:23, 11:23, 21:23
# 3 batalhas completas por sessao
# Disparo: 6s fixos
# Repair: HP <= 30%
# Manobra: quando recebe dano
#
# FILA (acima de 2500 pts):
#   Aplica → espera 50s
#   Se batalha iniciar → luta
#   Se nao iniciar → sai → espera 1 min → tenta de novo
#   Maximo 3 tentativas por batalha
#
# SEM PRIORIDADE: pvp nao interrompe cw/dm/pve

# Horarios fixos — minuto de inicio
PVP_HOURS="05 11 21"
PVP_MINUTE="23"
PVP_WINDOW=4  # minutos de janela apos o horario

_pvp_is_time() {
  local h m
  printf -v h '%(%H)T' -1
  printf -v m '%(%M)T' -1
  h=$((10#$h)); m=$((10#$m))
  local pm=$((10#$PVP_MINUTE))

  for pvp_h in $PVP_HOURS; do
    pvp_h=$((10#$pvp_h))
    if [ "$h" -eq "$pvp_h" ] && \
       [ "$m" -ge "$pm" ] && \
       [ "$m" -lt $(( pm + PVP_WINDOW )) ]; then
      return 0
    fi
  done
  return 1
}

pvp_mode() {
  [ "$FUNC_pvp" = "n" ] && return 0
  _pvp_is_time || return 0

  echo "[pvp] sessao iniciada (3 batalhas)"

  local battles_done=0
  while [ "$battles_done" -lt 3 ]; do
    battles_done=$(( battles_done + 1 ))
    echo "[pvp] batalha $battles_done/3"

    # Tenta entrar — max 3 tentativas
    local tries=0 entered=0
    while [ "$tries" -lt 3 ]; do
      tries=$(( tries + 1 ))
      echo "[pvp] tentativa $tries/3"

      if ! _pvp_join; then
        echo "[pvp] sem joinLink"
        break
      fi

      # Espera 50s para batalha iniciar
      if _pvp_wait_start 50; then
        entered=1
        break
      else
        # Batalha nao iniciou — sai e espera 1 min
        echo "[pvp] batalha nao iniciou — a sair"
        _pvp_leave
        echo "[pvp] aguarda 60s"
        sleep 60s
      fi
    done

    if [ "$entered" -eq 1 ]; then
      _pvp_fight
    else
      echo "[pvp] sem batalha apos 3 tentativas"
    fi

    sleep 3s
  done

  echo "[pvp] sessao concluida"
}

_pvp_join() {
  fetch_page "/pvp"
  if ! _session_active; then return 1; fi

  # joinLink — dois padroes possiveis
  local join
  join=$(grep -o -E \
    'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-joinLink' \
    "$SRC" | head -n1)

  [ -z "$join" ] && return 1

  echo "[pvp] a aplicar: $join"
  fetch_page "$join"
  sleep_rand 500 800
  return 0
}

_pvp_wait_start() {
  local max_wait="$1"
  local elapsed=0
  echo "[pvp] a aguardar inicio (max ${max_wait}s)..."

  while [ "$elapsed" -lt "$max_wait" ]; do
    # Batalha activa?
    if grep -q 'attackRegularShellLink' "$SRC" 2>/dev/null; then
      echo "[pvp] batalha iniciada!"
      return 0
    fi

    # Refresh na fila
    local ref
    ref=$(grep -o -E \
      'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-refreshLink' \
      "$SRC" | head -n1)
    [ -n "$ref" ] && fetch_page "$ref" || fetch_page "/pvp"

    sleep 5s
    elapsed=$(( elapsed + 5 ))
  done

  return 1
}

_pvp_leave() {
  local escape
  escape=$(grep -o -E \
    'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-escapeLink' \
    "$SRC" | head -n1)
  [ -n "$escape" ] && fetch_page "$escape" && sleep 2s
}

_pvp_fight() {
  local shots=0
  local timeout=$(( $(date +%s) + 600 ))
  local hp_max=""
  local last_repair=0
  local last_maneuver=0
  local repair_threshold=30

  echo "[pvp] em combate"

  while [ "$(date +%s)" -lt "$timeout" ]; do
    _session_active || break

    local atk repair maneuver escape
    atk=$(grep -o -E \
      'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-attackRegularShellLink' \
      "$SRC" | head -n1)
    repair=$(grep -o -E \
      'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-repairLink' \
      "$SRC" | head -n1)
    maneuver=$(grep -o -E \
      'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-maneuverLink' \
      "$SRC" | head -n1)
    escape=$(grep -o -E \
      'pvp[^"]*\?[0-9]+-[0-9]+\.ILinkListener-escapeLink' \
      "$SRC" | head -n1)

    # Fim de batalha
    [ -z "$atk" ] && [ -z "$escape" ] && {
      echo "[pvp] batalha terminou ($shots disparos)"
      break
    }

    # HP via funcao unificada (value-block — pvp usa mesmo padrao que assault)
    local hp_now
    hp_now=$(get_player_hp "value-block")
    [ -z "$hp_max" ] && [ -n "$hp_now" ] && hp_max="$hp_now"

    local now=$(date +%s)
    local since_repair=$(( now - last_repair ))
    local since_maneuver=$(( now - last_maneuver ))

    local hp_pct=""
    if [ -n "$hp_now" ] && [ "${hp_max:-0}" -gt 0 ] 2>/dev/null; then
      hp_pct=$(awk -v n="$hp_now" -v m="$hp_max" \
        'BEGIN{printf"%.0f",n/m*100}' 2>/dev/null)
    elif [ -z "$hp_now" ]; then
      echo "[pvp] AVISO: HP nao detectado"
    fi

    # REPAIR: HP <= 30%, tenta de 5 em 5s
    if [ -n "$hp_pct" ] && \
       [ "$hp_pct" -le "$repair_threshold" ] && \
       [ "$since_repair" -ge 5 ] 2>/dev/null; then
      last_repair=$now
      if [ -n "$repair" ]; then
        echo "[pvp] REPAIR HP: $hp_now (${hp_pct}%)"
        fetch_page_fast "$repair"
        continue
      fi
    fi

    # ── MANOBRA: apos receber dano ────────────────────────────
    if [ -n "$maneuver" ] && [ "$since_maneuver" -ge 20 ] 2>/dev/null; then
      if grep -q 'causou-lhe danos' "$SRC" 2>/dev/null; then
        echo "[pvp] manobra"
        fetch_page_fast "$maneuver"
        last_maneuver=$now
        continue
      fi
    fi

    # ── DISPARO: 6s fixos ─────────────────────────────────────
    [ -z "$atk" ] && { sleep 1s; continue; }
    sleep 6s
    fetch_page_fast "$atk"
    shots=$(( shots + 1 ))
    echo "[pvp] #${shots} | HP: ${hp_now:-?} (${hp_pct:-?}%)"

  done

  echo "[pvp] fim: $shots disparos"
}
