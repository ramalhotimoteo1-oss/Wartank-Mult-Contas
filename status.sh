#!/bin/bash
# status.sh — Helpers de estado por conta v1.0.0

# Escreve o estado actual da conta no ficheiro de status
# Usado pelo controlador para o painel em tempo real
_status_write() {
  local state="$1"
  local ts
  printf -v ts '%(%H:%M:%S)T' -1

  # Formato: STATE|ACC|LEVEL|FUEL|TIMESTAMP
  printf '%s|%s|%s|%s|%s\n' \
    "$state" \
    "${ACC:-?}" \
    "${PLAYER_LEVEL:-?}" \
    "${FUEL_CURRENT:-?}" \
    "$ts" \
    > "$STATUS_FILE"
}

# Lê o estado de um ficheiro de status (usado pelo controlador)
_status_read() {
  local file="$1"
  [ -f "$file" ] && cat "$file" || echo "offline|?|?|?|--:--:--"
}
