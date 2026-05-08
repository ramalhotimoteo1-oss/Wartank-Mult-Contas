#!/bin/bash
# battle.sh — Adiante a Combate v1.0.0 (multi-conta)

adiante_a_combate() {
  echo "[${ACC}] [battle] inicio"
  _status_write "battle"

  fetch_page "/battle"

  if ! grep -q '<title>Combate</title>' "$SRC" 2>/dev/null; then
    echo "[${ACC}] [battle] pagina invalida"
    log "battle pagina invalida" "WARN"
    return 0
  fi

  local la="${BATTLE_LA:-3}"
  local target_shots="${BATTLE_SHOTS:-9}"
  local timeout=$(( $(date +%s) + ${BATTLE_TIMEOUT:-600} ))
  local total_shots=0
  local ATK_LINK

  echo "[${ACC}] [battle] meta: $target_shots disparos | LA: ${la}s"

  while [ "$total_shots" -lt "$target_shots" ] && [ "$(date +%s)" -lt "$timeout" ]; do

    _session_active || { echo "[${ACC}] [battle] sessao perdida"; break; }

    if ! grep -q '<title>Combate</title>' "$SRC" 2>/dev/null; then
      echo "[${ACC}] [battle] saiu do combate"
      break
    fi

    ATK_LINK=$(grep -o -E \
      'battle\?[0-9]+-[0-9]+\.ILinkListener-[^"]+attackLink2' \
      "$SRC" | head -n1)

    if [ -z "$ATK_LINK" ]; then
      echo "[${ACC}] [battle] sem link — reload"
      fetch_page "/battle"
      ATK_LINK=$(grep -o -E \
        'battle\?[0-9]+-[0-9]+\.ILinkListener-[^"]+attackLink2' \
        "$SRC" | head -n1)
      [ -z "$ATK_LINK" ] && { echo "[${ACC}] [battle] sem link apos reload"; break; }
    fi

    sleep "${la}s"
    fetch_page "$ATK_LINK"
    sleep_rand 200 400
    total_shots=$(( total_shots + 1 ))
    echo "[${ACC}] [battle] disparo $total_shots/$target_shots"

  done

  echo "[${ACC}] [battle] fim: $total_shots disparos"
  log "battle fim: $total_shots disparos" "OK"
  _status_write "online"
}
