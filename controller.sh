#!/bin/bash
# controller.sh — Controlador multi-conta v1.1.0
#
# USO:
#   bash controller.sh          — inicia todas as contas
#   bash controller.sh stop     — para todos os workers
#   bash controller.sh status   — mostra painel uma vez
#   bash controller.sh add      — adiciona uma conta
#   bash controller.sh remove   — remove uma conta
#
# Contas guardadas em: ~/.wartank/accounts.conf
# Credenciais encriptadas em: ~/.wartank/<conta>/cript_file

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

# ── Sanitiza username para nome de ficheiro ──────────────────
_safe() { echo "$1" | tr -cd 'a-zA-Z0-9_-'; }

# ── Encripta / desencripta (igual ao original) ───────────────
_encrypt_creds() {
  printf '%s' "$1" | base64 -w 0 > "$2"
  chmod 600 "$2"
}
_decrypt_creds() {
  [ -f "$1" ] && base64 -d "$1" 2>/dev/null
}

# ── Lê password de forma oculta (igual ao original) ──────────
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

# ── Adiciona conta ───────────────────────────────────────────
cmd_add() {
  echo ""
  echo -e "  ${GOLD}${BOLD}Adicionar conta${RESET}"
  echo ""
  printf "  Username: "
  read -r username

  if [ -z "$username" ]; then
    echo -e "  ${RED}ERRO: username vazio${RESET}"; echo ""; return 1
  fi

  local safe
  safe=$(_safe "$username")
  local tmp="$BASE/$safe"
  mkdir -p "$tmp"
  local cript="$tmp/cript_file"

  if [ -f "$cript" ] && [ -s "$cript" ]; then
    echo -e "  ${GOLD}Conta '$username' já existe. Substituir password? (s/N)${RESET}"
    read -r confirm
    [ "$confirm" != "s" ] && [ "$confirm" != "S" ] && echo "" && return 0
  fi

  local password
  password=$(_read_password)

  if [ -z "$password" ]; then
    echo -e "  ${RED}ERRO: password vazia${RESET}"; echo ""; return 1
  fi

  # Guarda credenciais encriptadas (mesmo formato do original)
  _encrypt_creds "login=${username}&password=${password}" "$cript"
  unset password

  # Regista username no accounts.conf (só usernames, sem passwords)
  touch "$ACCOUNTS_CONF"
  chmod 600 "$ACCOUNTS_CONF"
  if ! grep -qx "$username" "$ACCOUNTS_CONF" 2>/dev/null; then
    echo "$username" >> "$ACCOUNTS_CONF"
  fi

  echo ""
  echo -e "  ${GREEN}[OK] Conta '$username' guardada em $ACCOUNTS_CONF${RESET}"
  echo ""
}

# ── Remove conta ─────────────────────────────────────────────
cmd_remove() {
  echo ""
  echo -e "  ${GOLD}${BOLD}Remover conta${RESET}"
  echo ""

  if [ ! -f "$ACCOUNTS_CONF" ] || [ ! -s "$ACCOUNTS_CONF" ]; then
    echo -e "  ${GRAY}Nenhuma conta registada.${RESET}"; echo ""; return
  fi

  echo "  Contas registadas:"
  echo ""
  while IFS= read -r u; do
    [[ -z "$u" || "$u" == \#* ]] && continue
    printf "    • %s\n" "$u"
  done < "$ACCOUNTS_CONF"

  echo ""
  printf "  Username a remover: "
  read -r username

  if grep -qx "$username" "$ACCOUNTS_CONF" 2>/dev/null; then
    sed -i "/^${username}$/d" "$ACCOUNTS_CONF"
    local safe
    safe=$(_safe "$username")
    rm -f "$BASE/$safe/cript_file" "$BASE/$safe/cookies.txt"
    rm -f "$STATUS_DIR/${safe}.status" "$PIDS_DIR/${safe}.pid"
    echo ""
    echo -e "  ${GREEN}[OK] '$username' removida.${RESET}"
  else
    echo -e "  ${RED}ERRO: '$username' não encontrada.${RESET}"
  fi
  echo ""
}

# ── Inicia worker de uma conta ───────────────────────────────
_start_worker() {
  local username="$1"
  local safe
  safe=$(_safe "$username")

  local tmp="$BASE/$safe"
  local cript="$tmp/cript_file"
  mkdir -p "$tmp"

  # Se não tem cript_file, pede password agora (1ª vez)
  if [ ! -f "$cript" ] || [ ! -s "$cript" ]; then
    echo ""
    echo -e "  ${GOLD}Primeira vez para '$username' — inserir password:${RESET}"
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

  rm -f "$cookie"
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

# ── Para todos os workers ────────────────────────────────────
cmd_stop() {
  echo ""
  echo -e "  ${GOLD}A parar todos os workers...${RESET}"
  echo ""
  local stopped=0

  for pid_file in "$PIDS_DIR"/*.pid; do
    [ -f "$pid_file" ] || continue
    local safe
    safe=$(basename "$pid_file" .pid)
    local pid
    pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
      kill -15 "$pid" 2>/dev/null; sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
      echo -e "  ${GREEN}[OK]${RESET} $safe (PID $pid)"
      stopped=$(( stopped + 1 ))
    else
      echo -e "  ${GRAY}[--]${RESET} $safe já parado"
    fi
    rm -f "$pid_file"
    local sf="$STATUS_DIR/${safe}.status"
    [ -f "$sf" ] && sed -i 's/^[^|]*/stopped/' "$sf" 2>/dev/null
  done

  echo ""
  echo -e "  ${GREEN}$stopped worker(s) parado(s).${RESET}"
  echo ""
}

# ── Cor por estado ───────────────────────────────────────────
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

# ── Próximo horário PVP ──────────────────────────────────────
_next_pvp() {
  local h m now_min
  printf -v h '%(%H)T' -1
  printf -v m '%(%M)T' -1
  now_min=$(( 10#$h * 60 + 10#$m ))

  for slot in \
    300 313 326 339 352 365 378 391 404 417 430 443 \
    456 469 482 495 508 521 534 547 560 573 586 599 \
    612 625 638 651 660 \
    780 793 806 819 832 845 858 871 884 897 910 923 \
    936 949 962 975 988 1001 1020 \
    1140 1153 1166 1179 1192 1205 1218 1231 1244 1257 1260; do
    if [ "$slot" -gt "$now_min" ]; then
      printf "%02d:%02d" "$(( slot / 60 ))" "$(( slot % 60 ))"
      return
    fi
  done
  echo "05:00 (amanhã)"
}

# ── Painel em tempo real ─────────────────────────────────────
_draw_panel() {
  local ts
  printf -v ts '%(%H:%M:%S)T' -1

  clear
  echo ""
  echo -e "  ${GOLD}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  Wartank Multi-Bot  |  %-28s${GOLD}${BOLD}║${RESET}\n" "$ts"
  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  %-13s %-12s %-5s %-5s %-9s${GOLD}${BOLD}║${RESET}\n" \
    "Conta" "Estado" "Niv" "Fuel" "Última"
  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

  local total=0 ativos=0

  for sf in "$STATUS_DIR"/*.status; do
    [ -f "$sf" ] || continue
    total=$(( total + 1 ))

    IFS='|' read -r state acc level fuel act_ts < "$sf"
    local safe
    safe=$(basename "$sf" .status)
    local pf="$PIDS_DIR/${safe}.pid"

    if [ -f "$pf" ]; then
      local pid; pid=$(cat "$pf")
      kill -0 "$pid" 2>/dev/null || state="morto"
    fi

    case "$state" in online|battle|pvp) ativos=$(( ativos + 1 )) ;; esac

    local sc; sc=$(_state_color "$state")
    printf "  ${GOLD}${BOLD}║${RESET}  %-13s %b %-5s %-5s %-9s${GOLD}${BOLD}║${RESET}\n" \
      "${acc:0:13}" "$sc" "${level:-?}" "${fuel:-?}" "${act_ts:---:--:--}"
  done

  [ "$total" -eq 0 ] && \
    printf "  ${GOLD}${BOLD}║${RESET}  %-50s${GOLD}${BOLD}║${RESET}\n" "Sem contas activas."

  echo -e "  ${GOLD}${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"
  printf "  ${GOLD}${BOLD}║${RESET}  %s activas / %s total   Próx. PVP: %-12s${GOLD}${BOLD}║${RESET}\n" \
    "$ativos" "$total" "$(_next_pvp)"
  echo -e "  ${GOLD}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${GRAY}Ctrl+C para parar tudo  |  actualiza em ${PANEL_INTERVAL}s${RESET}"
  echo ""
}

# ── Inicia todas as contas ───────────────────────────────────
cmd_start() {
  clear
  echo ""
  echo -e "  ${GOLD}${BOLD}Wartank Multi-Bot v1.1.0${RESET}"
  echo ""

  if [ ! -f "$ACCOUNTS_CONF" ] || [ ! -s "$ACCOUNTS_CONF" ]; then
    echo -e "  ${RED}Nenhuma conta registada.${RESET}"
    echo ""
    echo -e "  Adiciona a primeira conta com:"
    echo -e "    ${BOLD}bash controller.sh add${RESET}"
    echo ""
    exit 1
  fi

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

# ── Ponto de entrada ─────────────────────────────────────────
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
