#!/bin/bash
# battle.sh — Adiante a Combater v1.5.0
# HTML real confirmado — fluxo completo de 6 disparos
#
# FLUXO:
#   /battle → opponents-N-attackLink2 "Disparar"
#   → disparo → lastOpponentPanel-attackLink2 "Acabar de matar"
#   → disparo → lastOpponentPanel-attackLink2 "Destruir"
#   → disparo → opponents-N-attackLink2 "Disparar" (novo ciclo)
#
# REGEX UNIVERSAL: battle?X-X.ILinkListener-*-attackLink2
#   Cobre todos os estados sem logica condicional
#   SRC nao e recarregado apos disparo — resposta ja tem proximo link
#
# COMBUSTIVEL:
#   Cada disparo ~29-30 combustivel
#   3 inimigos = 9 disparos = 270 combustivel
#   Combustivel=0: /battle mostra inimigos mas NAO dispara
#   Estrategia: BATTLE_SHOTS=9 (3 inimigos), depois esperar recarga

adiante_a_combate() {
  [ "$FUNC_battle" = "n" ] && return 0

  echo "[battle] inicio"

  fetch_page "/battle"

  if ! grep -q '<title>Combate</title>' "$SRC" 2>/dev/null; then
    echo "[battle] pagina invalida: $(grep -o '<title>[^<]*</title>' "$SRC" 2>/dev/null)"
    return 0
  fi

  local la="${BATTLE_LA:-3}"
  local target_shots="${BATTLE_SHOTS:-9}"
  local timeout=$(( $(date +%s) + ${BATTLE_TIMEOUT:-600} ))
  local total_shots=0
  local ATK_LINK

  echo "[battle] meta: $target_shots disparos | LA: ${la}s"

  while [ "$total_shots" -lt "$target_shots" ] && [ "$(date +%s)" -lt "$timeout" ]; do

    _session_active || { echo "[battle] sessao perdida"; break; }

    # Fora da pagina de combate
    if ! grep -q '<title>Combate</title>' "$SRC" 2>/dev/null; then
      echo "[battle] saiu do combate"
      break
    fi

    # Regex universal — cobre Disparar, Acabar de matar, Destruir
    ATK_LINK=$(grep -o -E \
      'battle\?[0-9]+-[0-9]+\.ILinkListener-[^"]+attackLink2' \
      "$SRC" | head -n1)

    if [ -z "$ATK_LINK" ]; then
      echo "[battle] sem link — reload"
      fetch_page "/battle"
      ATK_LINK=$(grep -o -E \
        'battle\?[0-9]+-[0-9]+\.ILinkListener-[^"]+attackLink2' \
        "$SRC" | head -n1)
      [ -z "$ATK_LINK" ] && { echo "[battle] sem link apos reload"; break; }
    fi

    sleep "${la}s"
    fetch_page "$ATK_LINK"
    sleep_rand 200 400
    total_shots=$(( total_shots + 1 ))
    echo "[battle] disparo $total_shots/$target_shots"
    # NAO recarrega /battle — SRC ja tem proximo link

  done

  echo "[battle] fim: $total_shots disparos"
  go_hangar
}
