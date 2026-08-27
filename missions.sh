#!/bin/bash
# missions.sh — Missoes pessoais v2.0.0
#
# ALTERACOES v2.0.0:
#   + Regex mais largos para awardLink (com ou sem jsessionid no href)
#   + Normaliza o path para /missions/... antes do fetch (bug principal)
#   + Debug: lista links encontrados quando collected=0
#   + Tab Advanced sem depender so de "Advanced;jsessionid="
#   + Validacao de pagina menos fragil (nao exige M cirilico)
#   + Apos recolher, recarrega a MESMA tab (simples ou advanced)

missions_func() {
  [ "$FUNC_missions" = "n" ] && return 0

  echo "[missions] inicio"

  fetch_page "/missions/"
  if ! _session_active; then
    echo "[missions] sessao invalida"
    return
  fi

  # Pagina ok se tiver missions / award / titulo
  if ! grep -qiE 'missions-cc|awardLink|Miss|iss' "$SRC" 2>/dev/null; then
    echo "[missions] pagina invalida ou vazia"
    echo "[missions] title: $(grep -oE '<title>[^<]+</title>' "$SRC" 2>/dev/null | head -1)"
    return
  fi

  # Tab Simples
  echo "[missions] tab simples"
  _missions_collect_awards "/missions/"

  # Tab Complicados (Advanced)
  local adv_link
  adv_link=$(grep -oE 'href="[^"]*Advanced[^"]*"' "$SRC" 2>/dev/null \
    | sed 's/href="//;s/"$//' | head -n1)
  # Tambem: Advanced;jsessionid=XXX
  [ -z "$adv_link" ] && \
    adv_link=$(grep -oE 'Advanced;jsessionid=[A-Z0-9]+' "$SRC" 2>/dev/null | head -n1)

  if [ -n "$adv_link" ]; then
    case "$adv_link" in
      /*) ;;
      Advanced*|missions*) adv_link="/missions/${adv_link}" ;;
      *) adv_link="/missions/${adv_link}" ;;
    esac
    echo "[missions] tab complicados: $adv_link"
    fetch_page "$adv_link"
    _missions_collect_awards "$adv_link"
  else
    echo "[missions] tab advanced nao encontrada (ok se so houver simples)"
  fi

  echo "[missions] fim"
}

# Recolhe todos os awardLink da pagina actual.
# $1 = URL para reload apos cada recolha (manter a tab)
_missions_collect_awards() {
  local reload_url="${1:-/missions/}"
  local link collected=0
  local links

  links=$(grep -oE \
    '[^"<> ]*ILinkListener-missions-cc-[0-9]+-c-awardLink[^"<> ]*' \
    "$SRC" 2>/dev/null)

  # Fallback: qualquer awardLink em contexto missions
  if [ -z "$links" ]; then
    links=$(grep -oE \
      '[^"<> ]*missions-cc-[0-9]+[^"<> ]*awardLink[^"<> ]*' \
      "$SRC" 2>/dev/null)
  fi

  if [ -z "$links" ]; then
    echo "[missions] recolhidas: 0"
    # Debug util
    local sample
    sample=$(grep -oE 'ILinkListener[^"<> ]+' "$SRC" 2>/dev/null | head -5 | tr '\n' ' ')
    [ -n "$sample" ] && echo "[missions] debug ILinkListener: $sample"
    return
  fi

  while IFS= read -r link; do
    [ -z "$link" ] && continue

    link=$(_missions_normalize_link "$link")
    echo "[missions] a recolher: $link"
    fetch_page "$link"
    collected=$(( collected + 1 ))
    sleep_rand 400 700

    # Reload da mesma tab para proximos awards
    fetch_page "$reload_url"
  done <<< "$links"

  echo "[missions] recolhidas: $collected"
}

# Converte href relativo/jsessionid num path que o fetch_page entende
_missions_normalize_link() {
  local link="$1"

  # Tira aspas e lixo
  link=$(echo "$link" | sed 's/^["'\'']//;s/["'\'']$//')

  # ;jsessionid=XXX?40-1.ILinkListener-...  →  /missions/?40-1.ILinkListener-...
  # (o fetch_page reconstroi o jsessionid)
  if echo "$link" | grep -q '^;jsessionid='; then
    link=$(echo "$link" | sed 's/;jsessionid=[A-Z0-9]*//')
    echo "/missions/${link}"
    return
  fi

  # ?40-1.ILinkListener-missions-...
  if echo "$link" | grep -q '^\?'; then
    echo "/missions/${link}"
    return
  fi

  # Ja comeca por missions?
  if echo "$link" | grep -qi '^missions'; then
    echo "/${link}"
    return
  fi

  # Path absoluto /missions/...
  if echo "$link" | grep -q '^/'; then
    echo "$link"
    return
  fi

  # Default: prefixar /missions/
  echo "/missions/${link}"
}

special_combat_mission() {
  [ "${FUNC_special_missions:-y}" = "n" ] && return 0

  for path in /xpduel /bz2; do
    fetch_page "$path"
    if ! _session_active; then continue; fi

    local award_link
    award_link=$(grep -oE \
      '[^"<> ]*ILinkListener[^"<> ]*awardLink[^"<> ]*' \
      "$SRC" 2>/dev/null | head -n1)

    if [ -n "$award_link" ]; then
      award_link=$(_missions_normalize_link "$award_link")
      # Especiais podem nao ser /missions/ — se path for xpduel, manter no root
      case "$award_link" in
        /missions/\?*) award_link="/${path#/}${award_link#/missions}" ;;
      esac
      echo "[missions] recolher especial: $path → $award_link"
      fetch_page "$award_link"
      sleep_rand 400 700
      return
    fi
  done
}

collect_all_rewards() {
  missions_func
  special_combat_mission
}
