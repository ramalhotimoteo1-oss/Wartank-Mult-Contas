#!/bin/bash
# controller.sh — Controlador multi-conta LEVE v1.2.0
#
# USO:
#   bash controller.sh          — inicia todas as contas + painel
#   bash controller.sh stop     — para todos os workers
#   bash controller.sh status   — painel uma vez
#   bash controller.sh add      — adiciona conta
#   bash controller.sh remove   — remove conta
#
# Contas: ~/.wartank/accounts.conf (so usernames)
# Credenciais: ~/.wartank/<conta>/cript_file

BOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/.wartank"
ACCOUNTS_CONF="$BASE/accounts.conf"
PIDS_DIR="$BASE/pids"
STATUS_DIR="$BASE/status"
PANEL_INTERVAL=5

GOLD='\033[0;33m'
GREEN='\033[32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
GRAY='\033[02;37m'
BOLD='\033[1m'
RESET='\033[00m'

mkdir -p "$PIDS_DIR" "$STATUS_DIR" "$BASE"

_safe() { echo "$1" | tr -cd 'a-zA-Z0-9_-'; }

_encrypt_creds() {
  printf '%s' "$1" | base64 -w 0 > "$2"
  chmod 600 "$2"
}

_read_password() {
  local password="" char
  printf "  Password: "
  while IFS= read -r -s -n1 char; do
    [ -z "$char" ] && break
    if [ "$char" = $'\177' ] || [ "$char" = $'\010' ]; then
      [ -n "$password" ] && password="${password%?}" && printf '\b \b'
      continue
    fi
    password="${password}${char}"
    printf '*'
  done
  echo ""
  printf '%s' "$password"
}

cmd_add() {
  echo ""
  echo -e "  ${GOLD}${BOLD}Adicionar conta${RESET}"
  echo ""
  printf "  Username: "
  read -r username

  if [ -z "$username" ]; then
    echo -e "  ${RED}ERRO: username vazio${RESET}"; echo ""; return 1
  fi

  local safe tmp cript
  safe=$(_safe "$username")
  tmp="$BASE/$safe"
  mkdir -p "$tmp"
  cript="$tmp/cript_file"

  if [ -f "$cript" ] && [ -s "$cript" ]; then
    echo -e "  ${GOLD}Conta '$username' ja existe. Substituir password? (s/N)${RESET}"
    read -r confirm
    [ "$confirm" != "s" ] && [ "$confirm" != "S" ] && echo "" && return 0
  fi

  local password
  password=$(_read_password)
  if [ -z "$password" ]; then
    echo -e "  ${RED}ERRO: password vazia${RESET}"; echo ""; return 1
  fi

  _encrypt_creds "login=${username}&password=${password}" "$cript"
  unset password

  touch "$ACCOUNTS_CONF"
  chmod 600 "$ACCOUNTS_CONF"
  if ! grep -qx "$username" "$ACCOUNTS_CONF" 2>/dev/null; then
    echo "$username" >> "$ACCOUNTS_CONF"
  fi

  echo ""
  echo -e "  ${GREEN}[OK] Conta '$username' guardada${RESET}"
  echo ""
}

cmd_remove() {
  echo ""
  echo -e "  ${GOLD}${BOLD}Remover conta${RESET}"
  echo ""

  if [ ! -f "$ACCOUNTS_CONF" ] || [ ! -s "$ACCOUNTS_CONF" ]; then
    echo -e "  ${GRAY}Nenhuma conta registada.${RESET}"; echo ""; return
  fi

  echo "  Contas:"
  while IFS= read -r u; do
    [[ -z "$u" || "$u" == \#* ]] && continue
    printf "    - %s\n" "$u"
  done < "$ACCOUNTS_CONF"

  echo ""
  printf "  Username a remover: "
  read -r username

  if grep -qx "$username" "$ACCOUNTS_CONF" 2>/dev/null; then
    sed -i "/^${username}$/d" "$ACCOUNTS_CONF"
    local safe
    safe=$(_safe "$username")
    rm -rf "$BASE/$safe"
    rm -f "$STATUS_DIR/${safe}.status" "$PIDS_DIR/${safe}.pid"
    echo ""
    echo -e "  ${GREEN}[OK] '$username' removida.${RESET}"
  else
    echo -e "  ${RED}ERRO: '$username' nao encontrada.${RESET}"
  fi
  echo ""
}

_start_worker() {
  local username="$1"
  local safe tmp cript
  safe=$(_safe "$username")
  tmp="$BASE/$safe"
  cript="$tmp/cript_file"
  mkdir -p "$tmp"

  if [ ! -f "$cript" ] || [ ! -s "$cript" ]; then
    echo ""
    echo -e "  ${GOLD}Primeira vez para '$username' — password:${RESET}"
    local password
    password=$(_read_password)
    if [ -z "$password" ]; then
      echo -e "  ${RED}[!] Password vazia — a saltar '$username'${RESET}"
      return 1
    fi
    _encrypt_creds "login=${username}&password=${password}" "$cript"
    unset password
  fi

  local cookie="$tmp/cookies.txt"
  local log_f="$tmp/bot.log"
  local src="$tmp/SRC"
  local status_f="$STATUS_DIR/${safe}.status"

  echo "offline|$username|?|?|--:--:--" > "$status_f"

  ACC="$username" \
  TMP="$tmp" \
  COOKIE_FILE="$cookie" \
  CRIPT_FILE="$cript" \
  LOG_FILE="$log_f" \
  SRC="$src" \
  STATUS_FILE="$status_f" \
  bash "$BOT_DIR/worker.sh" >> "$log_f" 2>&1 &

  local pid=$!
  echo "$pid" > "$PIDS_DIR/${safe}.pid"
  echo -e "  ${GREEN}[+]${RESET} ${BOLD}${username}${RESET} — PID $pid"
}

cmd_stop() {
  echo ""
  echo -e "  ${GOLD}A parar workers...${RESET}"
  echo ""
  local stopped=0

  for pid_file in "$PIDS_DIR"/*.pid; do
    [ -f "$pid_file" ] || continue
    local safe pid
    safe=$(basename "$pid_file" .pid)
    pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
      kill -15 "$pid" 2>/dev/null; sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
      echo -e "  ${GREEN}[OK]${RESET} $safe (PID $pid)"
      stopped=$(( stopped + 1 ))
    else
      echo -e "  ${GRAY}[--]${RESET} $safe ja parado"
    fi
    rm -f "$pid_file"
    local sf="$STATUS_DIR/${safe}.status"
    [ -f "$sf" ] && sed -i 's/^[^|]*/stopped/' "$sf" 2>/dev/null
  done

  echo ""
  echo -e "  ${GREEN}$stopped worker(s) parado(s).${RESET}"
  echo ""
}

_state_color() {
  case "$1" in
    online)     printf "${GREEN}online    ${RESET}" ;;
    battle)     printf "${GOLD}battle    ${RESET}" ;;
    pvp)        printf "${CYAN}pvp       ${RESET}" ;;
    login)      printf "${GRAY}login...  ${RESET}" ;;
    reconectar) printf "${GOLD}reconect. ${RESET}" ;;
    erro_login) printf "${RED}erro login${RESET}" ;;
    morto)      printf "${RED}morto     ${RESET}" ;;
    stopped)    printf "${GRAY}stopped   ${RESET}" ;;
    *)          printf "${GRAY}offline   ${RESET}" ;;
  esac
}

# Proximo PvP: 05:23, 11:23, 21:23
_next_pvp() {
  local h m now_min
  printf -v h '%(%H)T' -1
  printf -v m '%(%M)T' -1
  now_min=$(( 10#$h * 60 + 10#$m ))

  for slot in 323 683 1283; do
    # 05:23=323, 11:23=683, 21:23=1283
    if [ "$slot" -gt "$now_min" ]; then
      printf "%02d:%02d" "$(( slot / 60 ))" "$(( slot % 60 ))"
      return
    fi
  done
  echo "05:23 (amanha)"
}

_draw_panel() {
  local ts
  printf -v ts '%(%H:%M:%S)T' -1

  clear
  echo ""
  echo -e "  ${GOLD}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  Wartank Multi LEVE  |  %-27s${GOLD}${BOLD}║${RESET}\n" "$ts"
  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  %-13s %-12s %-5s %-5s %-9s${GOLD}${BOLD}║${RESET}\n" \
    "Conta" "Estado" "Niv" "Fuel" "Ultima"
  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

  local total=0 ativos=0

  for sf in "$STATUS_DIR"/*.status; do
    [ -f "$sf" ] || continue
    total=$(( total + 1 ))

    IFS='|' read -r state acc level fuel act_ts < "$sf"
    local safe pf pid
    safe=$(basename "$sf" .status)
    pf="$PIDS_DIR/${safe}.pid"

    if [ -f "$pf" ]; then
      pid=$(cat "$pf")
      kill -0 "$pid" 2>/dev/null || state="morto"
    fi

    case "$state" in online|battle|pvp) ativos=$(( ativos + 1 )) ;; esac

    local sc
    sc=$(_state_color "$state")
    printf "  ${GOLD}${BOLD}║${RESET}  %-13s %b %-5s %-5s %-9s${GOLD}${BOLD}║${RESET}\n" \
      "${acc:0:13}" "$sc" "${level:-?}" "${fuel:-?}" "${act_ts:---:--:--}"
  done

  [ "$total" -eq 0 ] && \
    printf "  ${GOLD}${BOLD}║${RESET}  %-50s${GOLD}${BOLD}║${RESET}\n" "Sem contas activas."

  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  %s activas / %s total   Prox. PVP: %-11s${GOLD}${BOLD}║${RESET}\n" \
    "$ativos" "$total" "$(_next_pvp)"
  echo -e "  ${GOLD}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${GRAY}Ctrl+C para parar tudo  |  actualiza em ${PANEL_INTERVAL}s${RESET}"
  echo -e "  ${GRAY}Modulos: battle | pvp | cw | missoes | base | escolta | assault${RESET}"
  echo ""
}

cmd_start() {
  clear
  echo ""
  echo -e "  ${GOLD}${BOLD}Wartank Multi-Contas LEVE v1.2.0${RESET}"
  echo ""

  if [ ! -f "$ACCOUNTS_CONF" ] || [ ! -s "$ACCOUNTS_CONF" ]; then
    echo -e "  ${RED}Nenhuma conta registada.${RESET}"
    echo ""
    echo -e "  Adiciona a primeira conta:"
    echo -e "    ${BOLD}bash controller.sh add${RESET}"
    echo ""
    exit 1
  fi

  # Verifica modulos essenciais
  for m in worker.sh core.sh login.sh battle.sh; do
    if [ ! -f "$BOT_DIR/$m" ]; then
      echo -e "  ${RED}ERRO: falta $m na pasta do bot${RESET}"
      exit 1
    fi
  done

  local count=0
  while IFS= read -r username; do
    [[ -z "$username" || "$username" == \#* ]] && continue
    _start_worker "$username" && count=$(( count + 1 ))
    sleep 2
  done < "$ACCOUNTS_CONF"

  echo ""
  echo -e "  ${GREEN}$count conta(s) iniciada(s).${RESET}"
  echo ""

  trap 'echo ""; cmd_stop; exit 0' INT TERM

  while true; do
    _draw_panel
    sleep "$PANEL_INTERVAL"
  done
}

case "${1:-start}" in
  start)  cmd_start  ;;
  stop)   cmd_stop   ;;
  status) _draw_panel ;;
  add)    cmd_add    ;;
  remove) cmd_remove ;;
  *)
    echo ""
    echo -e "  ${BOLD}USO:${RESET} bash controller.sh [start|stop|status|add|remove]"
    echo ""
    ;;
esac
