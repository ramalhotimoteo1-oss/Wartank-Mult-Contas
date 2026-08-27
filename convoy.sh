#!/bin/bash
# convoy.sh — Escolta v1.6.0
#
# ALTERACOES v1.6.0:
#   + Detecta combate JA activo (fightView-attackRegular / smartAttack / attackSpecial)
#   + Nao depende so de findEnemy — se estiver a meio do fight, combate
#   + Fluxo:
#       A) Ja em combate (fightView-*) → _convoy_fight → startMasking
#       B) startFight / actLink → combate → startMasking
#       C) findEnemy → reconhecimento → startFight → combate → startMasking
#       D) Nada disso → cooldown no jogo, sai
#
# Sem timer interno no bot. Disponibilidade = HTML do jogo.

convoy_mode() {
  [ "$FUNC_convoy" = "n" ] && return 0

  echo "[convoy] inicio"

  fetch_page "/convoy"
  if ! _session_active; then return; fi

  if ! grep -q '<title>Escolta</title>' "$SRC" 2>/dev/null; then
    echo "[convoy] pagina invalida"
    return
  fi

  # Recolhe recompensas de missoes
  local award_link collected=0
  while IFS= read -r award_link; do
    [ -z "$award_link" ] && continue
    echo "[convoy] a recolher recompensa"
    fetch_page "$award_link"
    collected=$(( collected + 1 ))
    sleep_rand 300 500
    fetch_page "/convoy"
  done < <(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-missions-cc-[0-9]+-c-awardLink' \
    "$SRC" 2>/dev/null)

  [ "$collected" -gt 0 ] && echo "[convoy] $collected recompensa(s) recolhida(s)"

  # ── A) Ja em combate (fightView) ────────────────────────────
  if _convoy_in_fight; then
    echo "[convoy] combate ja activo"
    _convoy_fight
    _convoy_after_session
    return
  fi

  # ── B) Ecran do inimigo: ADIANTE A COMBATER / actLink ───────
  if _convoy_try_start_fight; then
    if _convoy_in_fight || grep -qE 'fightView-attack|ILinkListener-[^"]*attack' "$SRC" 2>/dev/null; then
      _convoy_fight
    fi
    _convoy_after_session
    return
  fi

  # ── C) Reconhecimento disponivel ────────────────────────────
  local find_link
  find_link=$(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-findEnemy' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$find_link" ]; then
    echo "[convoy] indisponivel (sem findEnemy / startFight / fightView)"
    echo "[convoy] links: $(grep -o -E 'convoy\?[^"]+' "$SRC" 2>/dev/null | head -8 | tr '\n' ' ')"
    return
  fi

  local enemies_killed=0
  local max_enemies=2

  while [ "$enemies_killed" -lt "$max_enemies" ]; do
    echo "[convoy] reconhecimento ($((enemies_killed+1))/$max_enemies)"

    find_link=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-findEnemy' \
      "$SRC" 2>/dev/null | head -n1)
    [ -z "$find_link" ] && {
      echo "[convoy] sem findEnemy — fim"
      break
    }

    fetch_page "$find_link"
    sleep_rand 800 1200

    if ! _convoy_try_start_fight; then
      if ! _convoy_in_fight; then
        echo "[convoy] sem inimigo"
        break
      fi
    fi

    local result
    result=$(_convoy_fight)

    if [ "$result" = "killed" ]; then
      enemies_killed=$(( enemies_killed + 1 ))
      echo "[convoy] inimigo destruido ($enemies_killed/$max_enemies)"
      find_link=$(grep -o -E \
        'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-findEnemy' \
        "$SRC" 2>/dev/null | head -n1)
      [ -z "$find_link" ] && break
    else
      echo "[convoy] inimigo nao destruido — sessao encerrada"
      break
    fi
  done

  echo "[convoy] combate fim ($enemies_killed inimigo(s))"
  _convoy_after_session
}

_convoy_in_fight() {
  grep -qE \
    'ILinkListener-root-fightView-(attackRegular|smartAttack|attackSpecial)' \
    "$SRC" 2>/dev/null
}

_convoy_try_start_fight() {
  local fight act

  fight=$(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-startFight' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -n "$fight" ]; then
    echo "[convoy] ADIANTE A COMBATER: $fight"
    fetch_page "$fight"
    sleep_rand 500 800
    return 0
  fi

  act=$(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-banner-actLink' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -n "$act" ]; then
    echo "[convoy] actLink: $act"
    fetch_page "$act"
    sleep_rand 500 800
    fight=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-startFight' \
      "$SRC" 2>/dev/null | head -n1)
    if [ -n "$fight" ]; then
      echo "[convoy] ADIANTE A COMBATER: $fight"
      fetch_page "$fight"
      sleep_rand 500 800
    fi
    return 0
  fi

  return 1
}

_convoy_after_session() {
  _convoy_start_reload
  echo "[convoy] fim"
}

_convoy_start_reload() {
  echo "[convoy] a iniciar recarregamento (startMasking)"

  fetch_page "/convoy"
  if ! _session_active; then
    echo "[convoy] sessao perdida — recarregamento nao iniciado"
    return
  fi

  local mask_link
  mask_link=$(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-startMasking' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -n "$mask_link" ]; then
    echo "[convoy] startMasking: $mask_link"
    fetch_page "$mask_link"
    sleep_rand 500 800
    echo "[convoy] recarregamento iniciado no jogo"
    return
  fi

  mask_link=$(grep -o -E \
    'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-[^"]*[Mm]ask[^"]*' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -n "$mask_link" ]; then
    echo "[convoy] mask fallback: $mask_link"
    fetch_page "$mask_link"
    sleep_rand 500 800
    return
  fi

  echo "[convoy] AVISO: startMasking nao encontrado"
  echo "[convoy] links: $(grep -o -E 'convoy\?[^"]+' "$SRC" 2>/dev/null | head -8 | tr '\n' ' ')"
}

_convoy_fight() {
  local shots=0
  local max_shots=3
  local la="${BATTLE_LA:-3}"

  echo "[convoy] em combate"

  while [ "$shots" -lt "$max_shots" ]; do
    _session_active || { echo "timeout"; return; }

    local atk_link
    atk_link=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-fightView-attackRegular' \
      "$SRC" 2>/dev/null | head -n1)
    [ -z "$atk_link" ] && atk_link=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-fightView-smartAttack' \
      "$SRC" 2>/dev/null | head -n1)
    [ -z "$atk_link" ] && atk_link=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-root-fightView-attackSpecial' \
      "$SRC" 2>/dev/null | head -n1)
    [ -z "$atk_link" ] && atk_link=$(grep -o -E \
      'convoy\?[0-9]+-[0-9]+\.ILinkListener-[^"]*attack[^"]*' \
      "$SRC" 2>/dev/null | head -n1)

    if [ -z "$atk_link" ]; then
      echo "killed"
      return
    fi

    sleep "${la}s"
    fetch_page "$atk_link"
    sleep_rand 200 400
    shots=$(( shots + 1 ))
    echo "[convoy] disparo $shots/$max_shots"

    if ! grep -qE 'fightView-attack|ILinkListener-[^"]*attack' "$SRC" 2>/dev/null; then
      echo "killed"
      return
    fi
  done

  echo "timeout"
}
