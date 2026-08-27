#!/bin/bash
# status.sh — Helpers de estado por conta v1.0.0

_status_write() {
  local state="$1"
  local ts
  printf -v ts '%(%H:%M:%S)T' -1
  [ -z "$STATUS_FILE" ] && return 0
  printf '%s|%s|%s|%s|%s\n' \
    "$state" \
    "${ACC:-?}" \
    "${PLAYER_LEVEL:-?}" \
    "${FUEL_CURRENT:-?}" \
    "$ts" \
    > "$STATUS_FILE"
}

_status_read() {
  local file="$1"
  [ -f "$file" ] && cat "$file" || echo "offline|?|?|?|--:--:--"
}
