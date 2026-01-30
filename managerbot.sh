#!/bin/bash

# =============================================================================
# MBT (Manager bot) — единая точка входа и все настройки
# Без параметров: интерактивное меню по цифрам
# С параметром: mbt.sh -r или -restart | -s или -swap | -suc или -stop-unwanted-containers
# =============================================================================

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Логи
LOGD() { echo -e "${yellow}[DEG] $* ${plain}"; }
LOGE() { echo -e "${red}[ERR] $* ${plain}"; }
LOGI() { echo -e "${green}[INF] $* ${plain}"; }

cur_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Настройки ---
VPNBOT_DIR="${VPNBOT_DIR:-/root/vpnbot}"
SWAPFILE="${SWAPFILE:-/swapfile}"
SWAPSIZE="${SWAPSIZE:-1536M}"
UNWANTED_CONTAINERS="${UNWANTED_CONTAINERS:-mtproto wireguard1 shadowsocks openconnect wireguard naive hysteria proxy dnstt adguard}"

# ОС (для fail2ban)
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  release="${ID:-unknown}"
  os_version=$(grep "^VERSION_ID" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d '.' || echo "0")
else
  release="unknown"
  os_version="0"
fi

# =============================================================================

usage() {
  echo -e "Использование: ${green}$(basename "$0")${plain} [команда]"
  echo ""
  echo "Без параметров — интерактивное меню."
  echo ""
  echo "Команды:"
  echo -e "  ${green}-restart${plain}, ${green}-r${plain}              Перезапуск бота (make r)"
  echo -e "  ${green}-swap${plain}, ${green}-s${plain}              Создать и включить swap (1.5 GB)"
  echo -e "  ${green}-stop-unwanted-containers${plain}, ${green}-suc${plain}   Остановить ненужные Docker-контейнеры"
  echo -e "  ${green}-crontab-reboot${plain}           Добавить в crontab автоперезапуск бота при загрузке"
  echo -e "  ${green}-crontab-suc${plain}             Добавить в crontab остановку контейнеров после загрузки"
  echo -e "  ${green}-bbr${plain}                     Подменю BBR (вкл/выкл)"
  echo -e "  ${green}-fail2ban${plain}, ${green}-f2b${plain}          Подменю Fail2ban (защита SSH)"
  echo -e "  ${green}-h${plain}, ${green}--help${plain}               Справка"
}

# Проверка root (для swap и docker)
check_root() {
  [[ $EUID -ne 0 ]] && LOGE "Эта операция требует прав root. Запустите с sudo." && exit 1
}

# --- Действия ---

run_restart() {
  LOGI "Перезапуск бота..."
  if [[ ! -d "$VPNBOT_DIR" ]]; then
    LOGE "Каталог не найден: $VPNBOT_DIR"
    exit 1
  fi
  (cd "$VPNBOT_DIR" && make r) || { LOGE "Ошибка make r"; exit 1; }
  LOGI "Готово."
}

run_swap() {
  check_root
  LOGI "Настройка swap..."
  if swapon --show | grep -q "$SWAPFILE"; then
    LOGI "Swap уже активен."
    return 0
  fi
  SWAP_MB="${SWAPSIZE%M}"
  if ! fallocate -l "$SWAPSIZE" "$SWAPFILE" 2>/dev/null; then
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="${SWAP_MB:-1536}"
  fi
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"
  grep -qF "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  sysctl vm.swappiness=10 2>/dev/null || true
  grep -qF 'vm.swappiness=10' /etc/sysctl.conf 2>/dev/null || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  LOGI "Swap создан и активирован:"
  swapon --show
  free -m
}

run_stop_containers() {
  check_root
  LOGI "Остановка ненужных контейнеров..."
  read -ra patterns <<< "$UNWANTED_CONTAINERS"
  ALL_CONTAINERS=$(docker ps -a --format "{{.Names}}" 2>/dev/null) || { LOGD "Docker недоступен или контейнеров нет."; return 0; }
  for container in $ALL_CONTAINERS; do
    for pattern in "${patterns[@]}"; do
      if [[ "$container" == *"$pattern"* ]]; then
        STATUS=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        if [[ "$STATUS" == "exited" || "$STATUS" == "created" || "$STATUS" == "dead" ]]; then
          LOGD "Контейнер '$container' уже остановлен (статус: $STATUS)."
        elif [[ "$STATUS" == "running" ]]; then
          LOGI "Останавливаю: $container"
          docker stop "$container" >/dev/null 2>&1
        else
          LOGD "Контейнер '$container' в состоянии '$STATUS', пропускаю."
        fi
        break
      fi
    done
  done
  LOGI "Ненужные контейнеры обработаны."
}

# --- Crontab: автоперезапуск бота при загрузке ---
CRONTAB_REBOOT_RESTART="@reboot cd $VPNBOT_DIR && make r"

crontab_has_reboot_restart() {
  crontab -l 2>/dev/null | grep -qF "$VPNBOT_DIR && make r"
}

crontab_add_reboot_restart() {
  if crontab_has_reboot_restart; then
    LOGD "Автоперезапуск бота уже включён в crontab."
    return 0
  fi
  (crontab -l 2>/dev/null; echo "$CRONTAB_REBOOT_RESTART") | crontab -
  LOGI "В crontab добавлено: $CRONTAB_REBOOT_RESTART"
}

crontab_remove_reboot_restart() {
  if ! crontab_has_reboot_restart; then
    LOGD "Автоперезапуск бота не найден в crontab."
    return 0
  fi
  crontab -l 2>/dev/null | grep -vF "$VPNBOT_DIR && make r" | crontab -
  LOGI "Автоперезапуск бота удалён из crontab."
}

crontab_menu_reboot_restart() {
  echo ""
  echo -e "${green}  Автоперезапуск бота при загрузке${plain}"
  echo -e "  ${blue}1.${plain} Включить (добавить в crontab)"
  echo -e "  ${blue}2.${plain} Выключить (удалить из crontab)"
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) crontab_add_reboot_restart; before_show_menu ;;
    2) crontab_remove_reboot_restart; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; crontab_menu_reboot_restart ;;
  esac
}

# --- Crontab: остановка контейнеров после загрузки ---
CRONTAB_REBOOT_SUC="@reboot (sleep 300 && cd $cur_dir && ./mbt.sh -suc)"

crontab_has_stop_containers() {
  crontab -l 2>/dev/null | grep -qF "mbt.sh -suc"
}

crontab_add_stop_containers() {
  if crontab_has_stop_containers; then
    LOGD "Остановка контейнеров после загрузки уже включена в crontab."
    return 0
  fi
  (crontab -l 2>/dev/null; echo "$CRONTAB_REBOOT_SUC") | crontab -
  LOGI "В crontab добавлено: $CRONTAB_REBOOT_SUC"
}

crontab_remove_stop_containers() {
  if ! crontab_has_stop_containers; then
    LOGD "Остановка контейнеров после загрузки не найдена в crontab."
    return 0
  fi
  crontab -l 2>/dev/null | grep -vF "mbt.sh -suc" | crontab -
  LOGI "Остановка контейнеров после загрузки удалена из crontab."
}

crontab_menu_stop_containers() {
  echo ""
  echo -e "${green}  Остановка контейнеров после загрузки${plain}"
  echo -e "  ${blue}1.${plain} Включить (добавить в crontab)"
  echo -e "  ${blue}2.${plain} Выключить (удалить из crontab)"
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) crontab_add_stop_containers; before_show_menu ;;
    2) crontab_remove_stop_containers; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; crontab_menu_stop_containers ;;
  esac
}

# --- BBR ---

enable_bbr() {
  check_root
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]] && [[ $(sysctl -n net.core.default_qdisc 2>/dev/null) =~ ^(fq|cake)$ ]]; then
    LOGI "BBR уже включён."
    before_show_menu
    return
  fi
  if [[ -d /etc/sysctl.d ]]; then
    {
      echo "#$(sysctl -n net.core.default_qdisc 2>/dev/null):$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
      echo "net.core.default_qdisc = fq"
      echo "net.ipv4.tcp_congestion_control = bbr"
    } > /etc/sysctl.d/99-bbr-x-ui.conf
    [[ -f /etc/sysctl.conf ]] && sed -i 's/^net.core.default_qdisc/# &/' /etc/sysctl.conf && sed -i 's/^net.ipv4.tcp_congestion_control/# &/' /etc/sysctl.conf
    sysctl --system >/dev/null 2>&1
  else
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
  fi
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]]; then
    LOGI "BBR успешно включён."
  else
    LOGE "Не удалось включить BBR. Проверьте конфигурацию системы."
  fi
}

disable_bbr() {
  check_root
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) != "bbr" ]] || [[ ! $(sysctl -n net.core.default_qdisc 2>/dev/null) =~ ^(fq|cake)$ ]]; then
    LOGD "BBR не включён."
    before_show_menu
    return
  fi
  if [[ -f /etc/sysctl.d/99-bbr-x-ui.conf ]]; then
    old_settings=$(head -1 /etc/sysctl.d/99-bbr-x-ui.conf | tr -d '#')
    sysctl -w net.core.default_qdisc="${old_settings%:*}" 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control="${old_settings#*:}" 2>/dev/null
    rm -f /etc/sysctl.d/99-bbr-x-ui.conf
    sysctl --system >/dev/null 2>&1
  else
    [[ -f /etc/sysctl.conf ]] && sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf && sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf && sysctl -p >/dev/null 2>&1
  fi
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) != "bbr" ]]; then
    LOGI "BBR отключён, используется CUBIC."
  else
    LOGE "Не удалось отключить BBR."
  fi
}

bbr_menu() {
  echo ""
  echo -e "${green}  BBR${plain}"
  echo -e "  ${blue}1.${plain} Включить BBR"
  echo -e "  ${blue}2.${plain} Отключить BBR"
  echo -e "  ${blue}0.${plain} Назад в главное меню"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) enable_bbr; before_show_menu ;;
    2) disable_bbr; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; bbr_menu ;;
  esac
}

# --- Fail2ban (защита SSH от брутфорса) ---

install_fail2ban_ssh() {
  check_root
  if ! command -v fail2ban-client &>/dev/null; then
    LOGI "Установка Fail2ban..."
    case "${release}" in
      ubuntu) apt-get update -qq && apt-get install -y -qq fail2ban ;;
      debian) apt-get update -qq && [[ "${os_version:-0}" -ge 12 ]] && apt-get install -y -qq python3-systemd 2>/dev/null; apt-get install -y -qq fail2ban ;;
      armbian) apt-get update -qq && apt-get install -y -qq fail2ban ;;
      fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol) dnf -y install -q fail2ban ;;
      centos) [[ "${VERSION_ID:-}" =~ ^7 ]] && { yum install -y -q epel-release; yum -y install -q fail2ban; } || dnf -y install -q fail2ban ;;
      arch|manjaro|parch) pacman -Sy --noconfirm fail2ban ;;
      alpine) apk add fail2ban ;;
      *) LOGE "ОС не поддерживается. Установите fail2ban вручную."; before_show_menu; return 1 ;;
    esac
    if ! command -v fail2ban-client &>/dev/null; then
      LOGE "Установка Fail2ban не удалась."
      before_show_menu
      return 1
    fi
    LOGI "Fail2ban установлен."
  else
    LOGD "Fail2ban уже установлен."
  fi
  # Включить jail для SSH (стандартный sshd)
  if ! fail2ban-client status sshd &>/dev/null; then
    mkdir -p /etc/fail2ban/jail.d
    echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local
    LOGI "Jail sshd включён."
  fi
  if [[ "$release" == "alpine" ]]; then
    rc-service fail2ban start 2>/dev/null || rc-service fail2ban restart 2>/dev/null
    rc-update add fail2ban 2>/dev/null
  else
    systemctl enable fail2ban 2>/dev/null
    systemctl start fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null
  fi
  LOGI "Fail2ban запущен. Защита SSH от брутфорса активна."
  before_show_menu
}

f2b_menu() {
  echo ""
  echo -e "${green}  Fail2ban — защита SSH${plain}"
  echo -e "  ${blue}1.${plain} Установить Fail2ban (защита SSH от брутфорса)"
  echo -e "  ${blue}2.${plain} Статус сервиса"
  echo -e "  ${blue}3.${plain} Перезапуск Fail2ban"
  echo -e "  ${blue}0.${plain} Назад в главное меню"
  echo -n "Выберите [0-3]: "
  read -r choice
  case "$choice" in
    1) install_fail2ban_ssh ;;
    2) systemctl status fail2ban 2>/dev/null || rc-service fail2ban status 2>/dev/null; before_show_menu ;;
    3) [[ "$release" == "alpine" ]] && rc-service fail2ban restart || systemctl restart fail2ban; LOGI "Fail2ban перезапущен."; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; f2b_menu ;;
  esac
}

# --- Интерактивное меню ---

# После выполнения команды: 0 — выйти, 1 — вернуться в меню. Возврат: 0 = в меню, 1 = выйти
prompt_back_or_exit() {
  echo ""
  echo -e "${yellow}0${plain} — Выход    ${yellow}1${plain} — Назад в меню"
  echo -n "Выберите [0/1]: "
  read -r r
  if [[ "$r" == "0" ]]; then
    LOGI "Выход."
    return 1
  fi
  return 0
}

# Нажать Enter для возврата в меню (как в x-ui)
before_show_menu() {
  echo && echo -n -e "${yellow}Нажмите Enter для возврата в меню: ${plain}" && read -r temp
  show_menu
}

show_menu() {
  while true; do
    echo ""
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -e "${green}         MBT (MANAGER BOT)             ${plain}"
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -e "  ${blue}1.${plain} Перезапуск бота (make r)"
    echo -e "  ${blue}2.${plain} Создать swap 1.5 GB"
    echo -e "  ${blue}3.${plain} Остановить ненужные Docker-контейнеры"
    echo -e "  ${blue}4.${plain} Автоперезапуск бота при загрузке (вкл/выкл)"
    echo -e "  ${blue}5.${plain} Остановка контейнеров после загрузки (вкл/выкл)"
    echo -e "  ${blue}6.${plain} BBR (вкл/выкл)"
    echo -e "  ${blue}7.${plain} Fail2ban (защита SSH)"
    echo -e "  ${blue}0.${plain} Выход"
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -n "Выберите действие [0-7]: "
    read -r choice
    case "$choice" in
      1) run_restart; prompt_back_or_exit || exit 0 ;;
      2) run_swap; prompt_back_or_exit || exit 0 ;;
      3) run_stop_containers; prompt_back_or_exit || exit 0 ;;
      4) crontab_menu_reboot_restart ;;
      5) crontab_menu_stop_containers ;;
      6) bbr_menu ;;
      7) f2b_menu ;;
      0) LOGI "Выход."; exit 0 ;;
      *) LOGE "Неверный выбор." ;;
    esac
  done
}

# =============================================================================
# Точка входа
# =============================================================================

cmd="${1:-}"
case "${cmd#--}" in
  -h|help|"")
    if [[ -z "$cmd" ]]; then
      show_menu
    else
      usage
      exit 0
    fi
    ;;
  -r|restart)
    run_restart
    ;;
  -s|swap)
    run_swap
    ;;
  -suc|-stop-unwanted-containers)
    run_stop_containers
    ;;
  -crontab-reboot)
    crontab_add_reboot_restart
    ;;
  -crontab-suc)
    crontab_add_stop_containers
    ;;
  -bbr)
    bbr_menu
    ;;
  -f2b|-fail2ban)
    f2b_menu
    ;;
  *)
    LOGE "Неизвестная команда: $cmd"
    usage
    exit 1
    ;;
esac
