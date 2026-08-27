#!/bin/bash
# base.sh — Base unificada v1.0.0
#
# Ordem de prioridade (sempre que disponivel):
#   1. Mina      — inicia producao de MINERIO (productions-0)
#   2. Poligono  — so buff GRATIS de ATAQUE (buffs-0-getFreeLink)
#   3. Sala de armas — kits / municoes conforme stock
#   4. Mercado   — prata→ouro, max 4x/dia em horarios fixos
#
# Tambem recolhe "Pegar" (takeProductionLink) na pagina /buildings.
#
# Regras importantes:
#   - Nao hardcodar quantidades/tempos de producao (variam por conta)
#   - Poligono: NUNCA activar buffs-1/2/3 (pago ou outros)
#   - Mercado: NUNCA trocar recursos por prata; so prata→ouro 4x/dia
#   - Armory: se kits <= 500 → produzir kit; senao → municao com menor stock

# Horarios de troca prata→ouro (4 por dia). Ajustavel no config.
MARKET_GOLD_HOURS="${MARKET_GOLD_HOURS:-06 12 18 22}"
MARKET_GOLD_MINUTE="${MARKET_GOLD_MINUTE:-27}"
MARKET_GOLD_WINDOW="${MARKET_GOLD_WINDOW:-3}"
LAST_MARKET_GOLD_SLOT=""

base_mode() {
  [ "${FUNC_buildings:-y}" = "n" ] && return 0

  echo "[base] inicio"

  # 0. Recolha generica na Base (Pegar)
  _base_collect_production

  # 1. Mina — minério
  _base_mine

  # 2. Poligono — ataque gratis
  _base_polygon

  # 3. Sala de armas
  _base_armory

  # 4. Mercado — prata→ouro (horarios)
  _base_market_gold

  echo "[base] fim"
}

# ── Recolher "Pegar" em /buildings ────────────────────────────
_base_collect_production() {
  fetch_page "/buildings"
  if ! _session_active; then return; fi

  local link n=0
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    echo "[base] a recolher: $link"
    fetch_page "$link"
    n=$(( n + 1 ))
    sleep_rand 300 500
    fetch_page "/buildings"
  done < <(grep -o -E \
    'buildings\?[0-9]+-[0-9]+\.ILinkListener-buildings-[0-9]+-building-rootBlock-actionPanel-takeProductionLink' \
    "$SRC" 2>/dev/null)

  [ "$n" -gt 0 ] && echo "[base] $n producao(oes) recolhida(s)"
}

# ── Mina: iniciar so MINERIO ──────────────────────────────────
_base_mine() {
  echo "[base/mina] verificar"

  fetch_page "/production/Mine"
  if ! _session_active; then return; fi

  # Se nao ha startProduce, ja esta a produzir ou pagina incorrecta
  local ore_link
  ore_link=$(grep -o -E \
    'Mine\?[0-9]+-[0-9]+\.ILinkListener-productions-0-production-startProduceLink' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$ore_link" ]; then
    # Ja em producao ou sem opcao de minério
    if grep -qE 'startProduceLink' "$SRC" 2>/dev/null; then
      echo "[base/mina] minério nao disponivel — outras opcoes ignoradas"
    else
      echo "[base/mina] sem start — provavelmente ja a produzir"
    fi
    return
  fi

  echo "[base/mina] a iniciar minério: $ore_link"
  fetch_page "/production/$ore_link"
  sleep_rand 500 800
  echo "[base/mina] producao de minério iniciada"
}

# ── Poligono: so ataque gratis (buffs-0) ──────────────────────
_base_polygon() {
  echo "[base/polygon] verificar"

  fetch_page "/polygon"
  if ! _session_active; then return; fi

  # Apenas buffs-0 (Intensificação do ataque)
  local free_atk
  free_atk=$(grep -o -E \
    'polygon\?[0-9]+-[0-9]+\.ILinkListener-buffs-0-buff-getFreeLink' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$free_atk" ]; then
    # Gratis de ataque ja usado / activo — nao tocar nos outros
    if grep -qE 'buffs-[123]-buff-getFreeLink' "$SRC" 2>/dev/null; then
      echo "[base/polygon] ataque gratis indisponivel (outros buffs ignorados)"
    elif grep -qiE 'ATIVO|Resta:' "$SRC" 2>/dev/null; then
      echo "[base/polygon] buff activo"
    else
      echo "[base/polygon] sem getFreeLink de ataque"
    fi
    return
  fi

  echo "[base/polygon] a activar ataque gratis: $free_atk"
  fetch_page "$free_atk"
  sleep_rand 500 800
  echo "[base/polygon] intensificacao do ataque activada"
}

# ── Sala de armas ─────────────────────────────────────────────
# Stock no HTML:
#   Granada explosiva / Projétil perfurante / Granada de carga oca / repairkit
# Producao:
#   0 = explosiva, 1 = perfurante, 2 = carga oca, 3 = kit
_base_armory() {
  echo "[base/armory] verificar"

  fetch_page "/production/Armory"
  if ! _session_active; then return; fi

  # Se nao ha nenhum startProduce, ja esta a produzir
  if ! grep -q 'startProduceLink' "$SRC" 2>/dev/null; then
    echo "[base/armory] sem start — provavelmente ja a produzir"
    return
  fi

  local he ap hc kit
  he=$(_base_armory_stock 'Granada explosiva')
  ap=$(_base_armory_stock 'Projétil perfurante')
  hc=$(_base_armory_stock 'Granada de carga oca')
  kit=$(_base_armory_stock_kit)

  echo "[base/armory] stock kit=${kit:-?} HE=${he:-?} AP=${ap:-?} HC=${hc:-?}"

  local idx="" label=""
  local kit_min="${ARMORY_KIT_MIN:-500}"

  # Prioridade 1: kits se <= limite
  if [ -n "$kit" ] && [ "$kit" -le "$kit_min" ] 2>/dev/null; then
    idx=3
    label="kit de reparacao"
  else
    # Prioridade 2: municao com menor quantidade
    he=${he:-0}; ap=${ap:-0}; hc=${hc:-0}
    local min=$he
    idx=0
    label="granada explosiva"
    if [ "$ap" -lt "$min" ] 2>/dev/null; then
      min=$ap; idx=1; label="projetil perfurante"
    fi
    if [ "$hc" -lt "$min" ] 2>/dev/null; then
      min=$hc; idx=2; label="carga oca"
    fi
  fi

  local link
  link=$(grep -o -E \
    "Armory\\?[0-9]+-[0-9]+\\.ILinkListener-productions-${idx}-production-startProduceLink" \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$link" ]; then
    echo "[base/armory] link de producao idx=$idx nao encontrado"
    return
  fi

  echo "[base/armory] a produzir: $label ($link)"
  fetch_page "/production/$link"
  sleep_rand 500 800
  echo "[base/armory] producao iniciada"
}

_base_armory_stock() {
  local name="$1"
  # Padrao: alt="Nome" ... numero  OU  title="Nome"/> N
  grep -o -E "alt=\"${name}\"[^0-9]*[0-9]+" "$SRC" 2>/dev/null \
    | grep -o -E '[0-9]+$' | head -n1
}

_base_armory_stock_kit() {
  # repairkit.gif"/> 741  ou similar
  local n
  n=$(grep -o -E 'repairkit[^0-9]*[0-9]+' "$SRC" 2>/dev/null \
    | grep -o -E '[0-9]+$' | head -n1)
  [ -n "$n" ] && { echo "$n"; return; }
  grep -o -E 'Kit de repara[^0-9]*[0-9]+' "$SRC" 2>/dev/null \
    | grep -o -E '[0-9]+$' | head -n1
}

# ── Mercado: prata → ouro, max 4x/dia em horarios fixos ───────
_base_market_gold() {
  [ "${FUNC_market_gold:-y}" = "n" ] && return 0

  local slot
  slot=$(_market_gold_slot)
  if [ -z "$slot" ]; then
    return 0
  fi
  if [ "$LAST_MARKET_GOLD_SLOT" = "$slot" ]; then
    echo "[base/market] ja trocou neste slot ($slot)"
    return 0
  fi

  echo "[base/market] horario de troca prata→ouro ($slot)"

  fetch_page "/market"
  if ! _session_active; then return; fi

  local buy
  buy=$(grep -o -E \
    'market\?[0-9]+-[0-9]+\.ILinkListener-xcSilverToGold-buyGold' \
    "$SRC" 2>/dev/null | head -n1)

  if [ -z "$buy" ]; then
    echo "[base/market] botao buyGold indisponivel"
    return
  fi

  echo "[base/market] a trocar: $buy"
  fetch_page "$buy"
  sleep_rand 500 800
  LAST_MARKET_GOLD_SLOT="$slot"
  echo "[base/market] troca prata→ouro feita (slot $slot)"
}

# Slot actual "HH:MM" se dentro da janela de um dos 4 horarios
_market_gold_slot() {
  local h m pm win
  printf -v h '%(%H)T' -1
  printf -v m '%(%M)T' -1
  h=$((10#$h)); m=$((10#$m))
  pm=$((10#${MARKET_GOLD_MINUTE:-27}))
  win=$((10#${MARKET_GOLD_WINDOW:-3}))

  local gh
  for gh in $MARKET_GOLD_HOURS; do
    gh=$((10#$gh))
    if [ "$h" -eq "$gh" ] && [ "$m" -ge "$pm" ] && [ "$m" -lt $(( pm + win )) ]; then
      printf '%02d:%02d' "$gh" "$pm"
      return
    fi
  done
  echo ""
}
