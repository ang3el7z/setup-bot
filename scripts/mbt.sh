#!/bin/bash

# =============================================================================
# MBT — единая точка входа и все настройки
# Без параметров: интерактивное меню по цифрам
#
# С параметром:
#   -r, -restart              Перезапуск бота (make r)
#   -s, -swap                 Подменю Swap (вкл/выкл); без меню — создать и включить swap (1.5 GB)
#   -suc [1|2|all|no-adguard], -stop-unwanted-containers   Остановить контейнеры (пресет 1 = с adguard, пресет 2 = без adguard; по умолчанию пресет 2)
#   -crontab-r, -crontab-reboot       Добавить в crontab автоперезапуск бота при загрузке
#   -crontab-suc [1|2|all|no-adguard], -crontab-stop-unwanted-containers   Добавить в crontab остановку контейнеров (по умолчанию пресет 2)
#   -bbr                     Подменю BBR (вкл/выкл)
#   -zram                    Подменю Zram (вкл/выкл)
#   -ipv6                    Подменю IPv6 (вкл/выкл)
#   -f2b, -fail2ban          Подменю Fail2ban (защита SSH)
#   -tz, -timezone           Выбор часового пояса (TZ в override.env)
#   -sub                     Копировать mbt_verify_user.php и внедрить хуки в bot.php (если их нет)
#   -all [1|2]               Все в одном; пресет контейнеров 1 (с adguard) или 2 (без adguard), по умолчанию 2
#   -all-not [1|2]           Отменить -all; пресет запуска контейнеров 1 или 2, по умолчанию 2
#   -h, --help               Справка
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
SCRIPT_NAME="$(basename "$0")"

# --- Настройки ---
VPNBOT_DIR="${VPNBOT_DIR:-/root/vpnbot}"
SWAPFILE="${SWAPFILE:-/swapfile}"
SWAPSIZE="${SWAPSIZE:-1536M}"
# Список контейнеров: Пресет 1 = с adguard, Пресет 2 = без adguard.
UNWANTED_CONTAINERS="${UNWANTED_CONTAINERS:-mtproto wireguard1 shadowsocks openconnect wireguard naive hysteria proxy dnstt adguard}"
# По умолчанию для -suc / -crontab-suc без аргумента: пресет 2 (без adguard).
SUC_PRESET="${SUC_PRESET:-no-adguard}"

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
  echo -e "  ${green}-swap${plain}, ${green}-s${plain}              Подменю Swap (вкл/выкл); из CLI — включить swap (1.5 GB)"
  echo -e "  ${green}-stop-unwanted-containers${plain}, ${green}-suc${plain} [1|2]   Остановить контейнеры (пресет 1 = с adguard, пресет 2 = без adguard; по умолчанию 2)"
  echo -e "  ${green}-crontab-reboot${plain}, ${green}-crontab-r${plain}   Добавить в crontab автоперезапуск бота при загрузке"
  echo -e "  ${green}-crontab-suc${plain}, ${green}-crontab-stop-unwanted-containers${plain} [1|2]   Добавить в crontab остановку контейнеров (по умолчанию пресет 2)"
  echo -e "  ${green}-bbr${plain}                     Подменю BBR (вкл/выкл)"
  echo -e "  ${green}-zram${plain}                    Подменю Zram (вкл/выкл)"
  echo -e "  ${green}-ipv6${plain}                    Подменю IPv6 (вкл/выкл)"
  echo -e "  ${green}-fail2ban${plain}, ${green}-f2b${plain}          Подменю Fail2ban (защита SSH)"
  echo -e "  ${green}-tz${plain}, ${green}-timezone${plain}           Выбор часового пояса (TZ в override.env)"
  echo -e "  ${green}-sub${plain}                     Копировать mbt_verify_user.php и внедрить хуки в bot.php"
  echo -e "  ${green}-all${plain} [1|2]               Все в одном (пресет контейнеров: 1 = с adguard, 2 = без adguard; по умолчанию 2)"
  echo -e "  ${green}-all-not${plain} [1|2]           Отменить -all (пресет запуска контейнеров 1 или 2; по умолчанию 2)"
  echo -e "  ${green}-h${plain}, ${green}--help${plain}               Справка"
  echo ""
  echo "Пресеты остановки контейнеров: 1 (с adguard), 2 (без adguard). По умолчанию — пресет 2. Переменная SUC_PRESET=all|no-adguard."
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

# Удалить swap (swapoff, убрать из fstab).
run_remove_swap() {
  check_root
  if ! swapon --show | grep -q "$SWAPFILE"; then
    LOGD "Swap по $SWAPFILE не активен."
    [[ -f /etc/fstab ]] && sed -i "\|^$SWAPFILE|d" /etc/fstab
    return 0
  fi
  swapoff "$SWAPFILE"
  [[ -f /etc/fstab ]] && sed -i "\|^$SWAPFILE|d" /etc/fstab
  LOGI "Swap отключён и убран из fstab."
}

swap_menu() {
  echo ""
  echo -e "${green}  Swap (1.5 GB)${plain}"
  echo -e "  ${blue}1.${plain} Включить swap (создать и активировать)"
  echo -e "  ${blue}2.${plain} Выключить swap (отключить и убрать из fstab)"
  echo -e "  ${blue}0.${plain} Назад в главное меню"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) run_swap; before_show_menu ;;
    2) run_remove_swap; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; swap_menu ;;
  esac
}

# Нормализует пресет: 1 или all = с adguard, 2 или no-adguard = без adguard. По умолчанию — пресет 2 (no-adguard).
normalize_suc_preset() {
  local p="${1:-$SUC_PRESET}"
  case "$p" in
    1|all) echo "all" ;;
    2|no-adguard) echo "no-adguard" ;;
    *) echo "no-adguard" ;;
  esac
}

# Возвращает список имён/паттернов для остановки по пресету (all | no-adguard).
# Пресет all = полный UNWANTED_CONTAINERS; no-adguard = тот же список без adguard.
get_suc_list() {
  local preset
  preset=$(normalize_suc_preset "${1:-$SUC_PRESET}")
  if [[ "$preset" == "no-adguard" ]]; then
    # Убрать adguard из списка
    echo "$UNWANTED_CONTAINERS" | tr ' ' '\n' | grep -vFx "adguard" | tr '\n' ' ' | sed 's/ $//'
  else
    echo "$UNWANTED_CONTAINERS"
  fi
}

# Человекочитаемое описание: что именно выключаем (явный список, без «с адгуардом»).
suc_list_description() {
  local list
  list=$(get_suc_list "$1")
  if [[ -z "$list" ]]; then
    echo "пустой список"
    return
  fi
  echo "$list" | tr ' ' ','
}

run_stop_containers() {
  check_root
  local preset
  preset=$(normalize_suc_preset "${1:-$SUC_PRESET}")
  local list
  list=$(get_suc_list "$preset")
  local desc
  desc=$(suc_list_description "$preset")
  LOGI "Остановка контейнеров по списку: $desc"
  read -ra patterns <<< "$list"
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
  LOGI "Контейнеры по списку обработаны."
}

# Запустить контейнеры по тому же списку (пресет 1 или 2). Запускаются только остановленные.
run_start_containers() {
  check_root
  local preset
  preset=$(normalize_suc_preset "${1:-$SUC_PRESET}")
  local list
  list=$(get_suc_list "$preset")
  local desc
  desc=$(suc_list_description "$preset")
  LOGI "Запуск контейнеров по списку: $desc"
  read -ra patterns <<< "$list"
  ALL_CONTAINERS=$(docker ps -a --format "{{.Names}}" 2>/dev/null) || { LOGD "Docker недоступен или контейнеров нет."; return 0; }
  for container in $ALL_CONTAINERS; do
    for pattern in "${patterns[@]}"; do
      if [[ "$container" == *"$pattern"* ]]; then
        STATUS=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
        if [[ "$STATUS" == "running" ]]; then
          LOGD "Контейнер '$container' уже запущен."
        elif [[ "$STATUS" == "exited" || "$STATUS" == "created" || "$STATUS" == "dead" ]]; then
          LOGI "Запускаю: $container"
          docker start "$container" >/dev/null 2>&1
        else
          LOGD "Контейнер '$container' в состоянии '$STATUS', пропускаю."
        fi
        break
      fi
    done
  done
  LOGI "Контейнеры по списку обработаны."
}

# Подменю: остановка или запуск контейнеров (пресет 1 = с adguard, пресет 2 = без adguard)
suc_menu_stop_containers() {
  echo ""
  echo -e "${green}  Docker-контейнеры по списку (остановить / запустить)${plain}"
  echo -e "  Пресет 1: mtproto, wireguard1, shadowsocks, openconnect, wireguard, naive, hysteria, proxy, dnstt, adguard"
  echo -e "  Пресет 2: mtproto, wireguard1, shadowsocks, openconnect, wireguard, naive, hysteria, proxy, dnstt"
  echo -e "  ${blue}1.${plain} Остановить — пресет 1 (с adguard)"
  echo -e "  ${blue}2.${plain} Остановить — пресет 2 (без adguard)"
  echo -e "  ${blue}3.${plain} Запустить — пресет 1 (с adguard)"
  echo -e "  ${blue}4.${plain} Запустить — пресет 2 (без adguard)"
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-4]: "
  read -r choice
  case "$choice" in
    1) run_stop_containers "all"; prompt_back_or_exit || exit 0 ;;
    2) run_stop_containers "no-adguard"; prompt_back_or_exit || exit 0 ;;
    3) run_start_containers "all"; prompt_back_or_exit || exit 0 ;;
    4) run_start_containers "no-adguard"; prompt_back_or_exit || exit 0 ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; suc_menu_stop_containers ;;
  esac
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
# Формирует строку crontab для пресета (all = пресет 1, no-adguard = пресет 2). По умолчанию пресет 2.
crontab_line_stop_containers() {
  local preset
  preset=$(normalize_suc_preset "${1:-no-adguard}")
  if [[ "$preset" == "no-adguard" ]]; then
    echo "@reboot (sleep 300 && cd $cur_dir && ./$SCRIPT_NAME -suc no-adguard)"
  else
    echo "@reboot (sleep 300 && cd $cur_dir && ./$SCRIPT_NAME -suc)"
  fi
}

crontab_has_stop_containers() {
  crontab -l 2>/dev/null | grep -qF "./$SCRIPT_NAME -suc"
}

crontab_add_stop_containers() {
  local preset
  preset=$(normalize_suc_preset "${1:-no-adguard}")
  local line
  line=$(crontab_line_stop_containers "$preset")
  if crontab_has_stop_containers; then
    # Удалить существующую запись (любой пресет), добавить новую
    crontab -l 2>/dev/null | grep -vF "./$SCRIPT_NAME -suc" | crontab -
  fi
  (crontab -l 2>/dev/null; echo "$line") | crontab -
  LOGI "В crontab добавлено (пресет: $preset): $line"
}

crontab_remove_stop_containers() {
  if ! crontab_has_stop_containers; then
    LOGD "Остановка контейнеров после загрузки не найдена в crontab."
    return 0
  fi
  crontab -l 2>/dev/null | grep -vF "./$SCRIPT_NAME -suc" | crontab -
  LOGI "Остановка контейнеров после загрузки удалена из crontab."
}

crontab_menu_stop_containers() {
  echo ""
  echo -e "${green}  Остановка контейнеров после загрузки${plain}"
  echo -e "  ${blue}1.${plain} Включить — пресет 1 (с adguard)"
  echo -e "  ${blue}2.${plain} Включить — пресет 2 (без adguard)"
  echo -e "  ${blue}3.${plain} Выключить (удалить из crontab)"
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-3]: "
  read -r choice
  case "$choice" in
    1) crontab_add_stop_containers "all"; before_show_menu ;;
    2) crontab_add_stop_containers "no-adguard"; before_show_menu ;;
    3) crontab_remove_stop_containers; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; crontab_menu_stop_containers ;;
  esac
}

# --- Часовой пояс (TZ в override.env для бота) ---
OVERRIDE_ENV="${VPNBOT_DIR}/override.env"

# Список: номер => "TZ|Подпись" (российские 1–12, затем зарубежные 13–25)
get_tz_list() {
  cat << 'TZLIST'
1|Europe/Kaliningrad|Калининград (UTC+2)
2|Europe/Moscow|Москва (UTC+3)
3|Europe/Samara|Самара (UTC+4)
4|Europe/Volgograd|Волгоград (UTC+3)
5|Asia/Yekaterinburg|Екатеринбург (UTC+5)
6|Asia/Omsk|Омск (UTC+6)
7|Asia/Krasnoyarsk|Красноярск (UTC+7)
8|Asia/Irkutsk|Иркутск (UTC+8)
9|Asia/Yakutsk|Якутск (UTC+9)
10|Asia/Vladivostok|Владивосток (UTC+10)
11|Asia/Magadan|Магадан (UTC+11)
12|Asia/Kamchatka|Камчатка (UTC+12)
13|UTC|UTC (UTC+0)
14|Europe/London|Лондон (UTC+0/+1)
15|Europe/Berlin|Берлин (UTC+1/+2)
16|Europe/Istanbul|Стамбул (UTC+3)
17|Asia/Dubai|Дубай (UTC+4)
18|Asia/Almaty|Алматы (UTC+6)
19|Asia/Tashkent|Ташкент (UTC+5)
20|Asia/Bangkok|Бангкок (UTC+7)
21|Asia/Singapore|Сингапур (UTC+8)
22|Asia/Shanghai|Шанхай (UTC+8)
23|Asia/Tokyo|Токио (UTC+9)
24|America/New_York|Нью-Йорк (UTC-5/-4)
25|America/Los_Angeles|Лос-Анджелес (UTC-8/-7)
TZLIST
}

run_set_timezone() {
  local tz_value="$1"
  if [[ -z "$tz_value" ]]; then
    LOGE "Часовой пояс не указан."
    return 1
  fi
  if [[ ! -d "$VPNBOT_DIR" ]]; then
    LOGE "Каталог не найден: $VPNBOT_DIR"
    return 1
  fi
  local env_file="$OVERRIDE_ENV"
  if [[ -f "$env_file" ]]; then
    # Удалить старую строку TZ=, если есть
    grep -v '^TZ=' "$env_file" > "${env_file}.tmp" 2>/dev/null && mv "${env_file}.tmp" "$env_file"
  fi
  echo "TZ=$tz_value" >> "$env_file"
  LOGI "В $env_file записано: TZ=$tz_value"
  LOGI "Чтобы применить к боту, перезапустите его (п.1 меню или: make r в $VPNBOT_DIR)."
}

tz_menu() {
  echo ""
  echo -e "${green}  Часовой пояс (TZ для бота)${plain}"
  echo -e "  Запись в ${blue}$OVERRIDE_ENV${plain}. Бот подхватит TZ после перезапуска."
  echo ""
  echo -e "  ${yellow}Россия:${plain}"
  get_tz_list | while IFS='|' read -r num tz label; do
    if [[ "$num" -le 12 ]]; then
      echo -e "  ${blue}${num}.${plain} $label ($tz)"
    fi
  done
  echo -e "  ${yellow}Другие:${plain}"
  get_tz_list | while IFS='|' read -r num tz label; do
    if [[ "$num" -ge 13 ]]; then
      echo -e "  ${blue}${num}.${plain} $label ($tz)"
    fi
  done
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-25]: "
  read -r choice
  if [[ "$choice" == "0" ]]; then
    show_menu
    return
  fi
  local picked
  picked=$(get_tz_list | while IFS='|' read -r num tz label; do
    if [[ "$num" == "$choice" ]]; then echo "$tz"; break; fi
  done)
  if [[ -n "$picked" ]]; then
    run_set_timezone "$picked"
    before_show_menu
  else
    LOGE "Неверный выбор."
    tz_menu
  fi
}

# --- BBR ---

enable_bbr() {
  check_root
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]] && [[ $(sysctl -n net.core.default_qdisc 2>/dev/null) =~ ^(fq|cake)$ ]]; then
    LOGI "BBR уже включён."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
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
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
}

disable_bbr() {
  check_root
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) != "bbr" ]] || [[ ! $(sysctl -n net.core.default_qdisc 2>/dev/null) =~ ^(fq|cake)$ ]]; then
    LOGD "BBR не включён."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
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
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
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

# --- Zram (сжатый swap в RAM: zstd, 60%, приоритет 100) ---
run_zram_enable() {
  check_root
  if systemctl is-active --quiet zramswap 2>/dev/null; then
    LOGI "Zram уже активен."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
    return 0
  fi
  if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y zram-tools
  else
    LOGE "zram-tools устанавливается через apt (Debian/Ubuntu). Установите вручную: apt install zram-tools"
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
    return 1
  fi
  local cfg="/etc/default/zramswap"
  if [[ -f "$cfg" ]]; then
    sed -i 's/^ALGO=.*/ALGO=zstd/' "$cfg"
    sed -i 's/^PERCENT=.*/PERCENT=60/' "$cfg"
    sed -i 's/^PRIORITY=.*/PRIORITY=100/' "$cfg"
    grep -q '^ALGO=' "$cfg" || echo 'ALGO=zstd' >> "$cfg"
    grep -q '^PERCENT=' "$cfg" || echo 'PERCENT=60' >> "$cfg"
    grep -q '^PRIORITY=' "$cfg" || echo 'PRIORITY=100' >> "$cfg"
  else
    echo 'ALGO=zstd' > "$cfg"
    echo 'PERCENT=60' >> "$cfg"
    echo 'PRIORITY=100' >> "$cfg"
  fi
  systemctl enable zramswap 2>/dev/null
  systemctl restart zramswap 2>/dev/null
  if systemctl is-active --quiet zramswap 2>/dev/null; then
    LOGI "Zram включён (zstd, 60%, приоритет 100)."
  else
    LOGE "Не удалось запустить zramswap. Проверьте: systemctl status zramswap"
  fi
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
}

run_zram_disable() {
  check_root
  if ! systemctl is-active --quiet zramswap 2>/dev/null; then
    LOGD "Zram не активен."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
    return 0
  fi
  systemctl stop zramswap 2>/dev/null
  systemctl disable zramswap 2>/dev/null
  LOGI "Zram отключён."
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
}

zram_menu() {
  echo ""
  echo -e "${green}  Zram (сжатый swap в RAM)${plain}"
  echo -e "  ${blue}1.${plain} Включить (zstd, 60% RAM, приоритет 100)"
  echo -e "  ${blue}2.${plain} Выключить"
  echo -e "  ${blue}0.${plain} Назад в главное меню"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) run_zram_enable; before_show_menu ;;
    2) run_zram_disable; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; zram_menu ;;
  esac
}

# --- IPv6 (вкл/выкл) ---

ipv6_disabled_now() {
  [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) == "1" ]]
}

enable_ipv6() {
  check_root
  if ! ipv6_disabled_now; then
    LOGD "IPv6 уже включён."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
    return
  fi
  rm -f /etc/sysctl.d/99-ipv6-mbt.conf
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 2>/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 2>/dev/null
  sysctl --system >/dev/null 2>&1
  if ! ipv6_disabled_now; then
    LOGI "IPv6 включён."
  else
    LOGE "Не удалось включить IPv6."
  fi
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
}

disable_ipv6() {
  check_root
  if ipv6_disabled_now; then
    LOGD "IPv6 уже отключён."
    [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
    return
  fi
  {
    echo "net.ipv6.conf.all.disable_ipv6 = 1"
    echo "net.ipv6.conf.default.disable_ipv6 = 1"
  } > /etc/sysctl.d/99-ipv6-mbt.conf
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null
  sysctl --system >/dev/null 2>&1
  if ipv6_disabled_now; then
    LOGI "IPv6 отключён."
  else
    LOGE "Не удалось отключить IPv6."
  fi
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
}

ipv6_menu() {
  echo ""
  echo -e "${green}  IPv6${plain}"
  echo -e "  ${blue}1.${plain} Включить IPv6"
  echo -e "  ${blue}2.${plain} Отключить IPv6"
  echo -e "  ${blue}0.${plain} Назад в главное меню"
  echo -n "Выберите [0-2]: "
  read -r choice
  case "$choice" in
    1) enable_ipv6; before_show_menu ;;
    2) disable_ipv6; before_show_menu ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; ipv6_menu ;;
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
      *) LOGE "ОС не поддерживается. Установите fail2ban вручную."; [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu; return 1 ;;
    esac
    if ! command -v fail2ban-client &>/dev/null; then
      LOGE "Установка Fail2ban не удалась."
      [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
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
  [[ -z "$RUN_ALL_IN_ONE" ]] && before_show_menu
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

# --- Sub: копировать mbt_verify_user.php и внедрить хуки в bot.php (если их ещё нет) ---

run_sub() {
  local app_dir="$VPNBOT_DIR/app"
  local bot_php="$app_dir/bot.php"
  local mbt_dst="$app_dir/mbt_verify_user.php"
  local mbt_url="${MBT_VERIFY_USER_URL:-https://raw.githubusercontent.com/ang3el7z/mbt/main/app/mbt_verify_user.php}"

  if [[ ! -f "$bot_php" ]]; then
    LOGE "Не найден bot.php: $bot_php (VPNBOT_DIR=$VPNBOT_DIR)"
    return 1
  fi
  # Глобально отключаем превью ссылок
  sed -i -E "s@^[[:space:]]*//[[:space:]]*'disable_web_page_preview'[[:space:]]*=>[[:space:]]*true,@                'disable_web_page_preview' => true,@" "$bot_php"

  mkdir -p "$app_dir"
  LOGI "Скачиваю mbt_verify_user.php: $mbt_url"
  if command -v curl >/dev/null 2>&1; then
    curl -sL -o "$mbt_dst" "$mbt_url" || { LOGE "Не удалось скачать mbt_verify_user.php"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$mbt_dst" "$mbt_url" || { LOGE "Не удалось скачать mbt_verify_user.php"; return 1; }
  else
    LOGE "Нужен curl или wget для загрузки."
    return 1
  fi
  [[ ! -s "$mbt_dst" ]] && { LOGE "Скачанный файл пустой."; return 1; }
  LOGI "Готово: mbt_verify_user.php -> $mbt_dst"

  if grep -q "mbt_verify_user\.php" "$bot_php"; then
    LOGI "Правки MBT уже есть в bot.php, пропуск."
    LOGI "Пункт 10 выполнен. Перезапустите бота при необходимости (п. 1)."
    return 0
  fi

  # Патч 1: auth() — вставить блок подписки перед exit для не-админа
  local auth_patched=0
  if grep -q 'elseif.*!in_array.*input.*from.*admin' "$bot_php"; then
    awk -v sq="'" '
      /elseif[[:space:]]*\([[:space:]]*!in_array\(.*admin.*\).*\{[[:space:]]*$/ {
        in_else=1
        print
        next
      }
      in_else && /exit[[:space:]]*;/ {
        print "            // [MBT] Подписка: callback /verifySub обрабатывает action(); иначе — показываем подписку и выходим."
        print "            if (preg_match(" sq "~^/verifySub~" sq ", $this->input[" sq "callback" sq "] ?? " sq sq ")) {"
        print "                return;"
        print "            }"
        print "            require_once __DIR__ . " sq "/mbt_verify_user.php" sq ";"
        print "            mbt_verify_user_show($this);"
        print "            exit;"
        in_else=0
        next
      }
      in_else && /^\s*\}\s*$/ { in_else=0 }
      { print }
    ' "$bot_php" > "$bot_php.awked" 2>/dev/null && mv "$bot_php.awked" "$bot_php" && auth_patched=1
  fi
  if [[ "$auth_patched" -eq 1 ]]; then
    LOGI "Правка auth() внесена."
  else
    LOGI "auth(): блок не-админа не найден или формат другой — внесите правку вручную: https://github.com/ang3el7z/mbt/blob/main/app/mbt_verify_user.md"
  fi

  # Патч 2: action() — первый case для /verifySub
  if ! grep -q "verifySub.*mbt_verify_user_callback" "$bot_php"; then
    local case_line
    case_line=$(grep -nE "switch[[:space:]]*\([[:space:]]*true[[:space:]]*\)" "$bot_php" | head -1 | cut -d: -f1)
    if [[ -n "$case_line" ]]; then
      local insert_line=$((case_line + 1))
      {
        head -n "$case_line" "$bot_php"
        echo "            // [MBT] Подписка: маршрут /verifySub в mbt_verify_user.php"
        echo "            case preg_match('~^/verifySub(?:\s+(?P<arg>.+))?\$~', \$this->input['callback'], \$m):"
        echo "                require_once __DIR__ . '/mbt_verify_user.php';"
        echo "                mbt_verify_user_callback(\$this, \$m['arg'] ?? 'list');"
        echo "                break;"
        tail -n +"$insert_line" "$bot_php"
      } > "$bot_php.new" 2>/dev/null && mv "$bot_php.new" "$bot_php" && LOGI "Правка action() (case /verifySub) внесена."
    else
      LOGI "action(): switch (true) не найден — внесите правку вручную: https://github.com/ang3el7z/mbt/blob/main/app/mbt_verify_user.md"
    fi
  fi

  LOGI "Пункт 10 выполнен. Перезапустите бота при необходимости (п. 1)."
}

# --- Все в одном ---
# Пресет для контейнеров: 1 = с adguard, 2 = без adguard. По умолчанию 2.
run_all_in_one() {
  check_root
  local preset
  preset=$(normalize_suc_preset "${1:-no-adguard}")
  export RUN_ALL_IN_ONE=1
  LOGI "Все в одном (пресет контейнеров: $preset): swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban..."
  run_swap
  LOGI "[1/8] Swap готов."
  run_stop_containers "$preset"
  LOGI "[2/8] Контейнеры обработаны (пресет: $preset)."
  crontab_add_reboot_restart
  LOGI "[3/8] Автозапуск бота добавлен в crontab."
  crontab_add_stop_containers "$preset"
  LOGI "[4/8] Остановка контейнеров после загрузки добавлена в crontab (пресет: $preset)."
  enable_bbr
  LOGI "[5/8] BBR включён."
  run_zram_enable
  LOGI "[6/8] Zram включён."
  disable_ipv6
  LOGI "[7/8] IPv6 отключён."
  install_fail2ban_ssh
  LOGI "[8/8] Fail2ban включён."
  unset RUN_ALL_IN_ONE
  LOGI "Все в одном выполнено."
  before_show_menu
}

# Отменить всё, что сделал -all. Пресет — какие контейнеры запускать (1 или 2), по умолчанию 2.
run_all_not() {
  check_root
  local preset
  preset=$(normalize_suc_preset "${1:-no-adguard}")
  export RUN_ALL_IN_ONE=1
  LOGI "Отмена «все в одном» (запуск контейнеров пресет $preset): контейнеры, crontab, BBR, Zram, IPv6, swap, Fail2ban..."
  run_start_containers "$preset"
  LOGI "[1/7] Контейнеры по списку (пресет: $preset) запущены."
  crontab_remove_reboot_restart
  LOGI "[2/7] Автоперезапуск бота удалён из crontab."
  crontab_remove_stop_containers
  LOGI "[3/7] Остановка контейнеров после загрузки удалена из crontab."
  disable_bbr
  LOGI "[4/7] BBR отключён."
  run_zram_disable
  LOGI "[5/7] Zram отключён."
  enable_ipv6
  LOGI "[6/7] IPv6 включён."
  run_remove_swap
  LOGI "[7/7] Swap отключён."
  if command -v fail2ban-client &>/dev/null; then
    if [[ "$release" == "alpine" ]]; then
      rc-service fail2ban stop 2>/dev/null; rc-update del fail2ban 2>/dev/null
    else
      systemctl stop fail2ban 2>/dev/null; systemctl disable fail2ban 2>/dev/null
    fi
    LOGI "Fail2ban остановлен и отключён при загрузке."
  else
    LOGD "Fail2ban не установлен, пропуск."
  fi
  unset RUN_ALL_IN_ONE
  LOGI "Отмена «все в одном» выполнена."
  before_show_menu
}

# Подменю «Все в одном»: включить (пресет 1 или 2) или выключить.
all_menu() {
  echo ""
  echo -e "${green}  Все в одном${plain}"
  echo -e "  Пресет контейнеров: 1 = с adguard, 2 = без adguard"
  echo -e "  ${blue}1.${plain} Включить — пресет 1 (контейнеры с adguard)"
  echo -e "  ${blue}2.${plain} Включить — пресет 2 (контейнеры без adguard)"
  echo -e "  ${blue}3.${plain} Выключить (запустить контейнеры пресета 2, откат остального)"
  echo -e "  ${blue}0.${plain} Назад"
  echo -n "Выберите [0-3]: "
  read -r choice
  case "$choice" in
    1) run_all_in_one "all" ;;
    2) run_all_in_one "no-adguard" ;;
    3) run_all_not "no-adguard" ;;
    0) show_menu ;;
    *) LOGE "Неверный выбор."; all_menu ;;
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
    echo -e "${green}                MBT                    ${plain}"
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -e "  ${blue}1.${plain} Перезапуск бота (make r)"
    echo -e "  ${blue}2.${plain} Swap (вкл/выкл)"
    echo -e "  ${blue}3.${plain} Docker-контейнеры по списку (остановить / запустить)"
    echo -e "  ${blue}4.${plain} Автоперезапуск бота при загрузке (вкл/выкл)"
    echo -e "  ${blue}5.${plain} Остановка контейнеров после загрузки (вкл/выкл)"
    echo -e "  ${blue}6.${plain} BBR (вкл/выкл)"
    echo -e "  ${blue}7.${plain} Zram (вкл/выкл)"
    echo -e "  ${blue}8.${plain} IPv6 (вкл/выкл)"
    echo -e "  ${blue}9.${plain} Fail2ban (защита SSH)"
    echo -e "  ${blue}10.${plain} Все в одном (вкл/выкл)"
    echo -e "  ${blue}11.${plain} Подписка: mbt_verify_user.php + правки в bot.php (если нет)"
    echo -e "  ${blue}12.${plain} Часовой пояс (TZ для бота)"
    echo -e "  ${blue}0.${plain}  Выход"
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -n "Выберите действие [0-12]: "
    read -r choice
    case "$choice" in
      1) run_restart; prompt_back_or_exit || exit 0 ;;
      2) swap_menu ;;
      3) suc_menu_stop_containers ;;
      4) crontab_menu_reboot_restart ;;
      5) crontab_menu_stop_containers ;;
      6) bbr_menu ;;
      7) zram_menu ;;
      8) ipv6_menu ;;
      9) f2b_menu ;;
      10) all_menu ;;
      11) run_sub; prompt_back_or_exit || exit 0 ;;
      12) tz_menu ;;
      0) LOGI "Выход."; exit 0 ;;
      "") ;;   # пустой ввод — показать меню снова
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
      if [[ ! -t 0 ]]; then
        LOGE "Для меню нужен интерактивный терминал. Запустите: mbt   или укажите команду: mbt -r"
        usage
        exit 1
      fi
      show_menu
    else
      usage
      exit 0
    fi
    ;;
  -r|restart)
    run_restart
    ;;
  -s|-swap)
    if [[ -t 0 ]]; then
      swap_menu
    else
      run_swap
    fi
    ;;
  -suc|-stop-unwanted-containers)
    run_stop_containers "${2:-no-adguard}"
    ;;
  -crontab-r|-crontab-reboot)
    crontab_add_reboot_restart
    ;;
  -crontab-suc|-crontab-stop-unwanted-containers)
    crontab_add_stop_containers "${2:-no-adguard}"
    ;;
  -bbr)
    bbr_menu
    ;;
  -zram)
    zram_menu
    ;;
  -ipv6)
    ipv6_menu
    ;;
  -f2b|-fail2ban)
    f2b_menu
    ;;
  -sub)
    run_sub
    ;;
  -tz|-timezone)
    tz_menu
    ;;
  -all)
    if [[ -z "${2:-}" ]] && [[ -t 0 ]]; then
      echo ""
      echo -e "${green}  Все в одном — выбор пресета${plain}"
      echo -e "  ${blue}1.${plain} Пресет 1 (контейнеры с adguard)"
      echo -e "  ${blue}2.${plain} Пресет 2 (контейнеры без adguard, по умолчанию)"
      echo -n "Выберите пресет [1/2, по умолчанию 2]: "
      read -r preset_choice
      case "${preset_choice:-2}" in
        1) run_all_in_one "all" ;;
        2) run_all_in_one "no-adguard" ;;
        *) LOGE "Неверный выбор, используется пресет 2."; run_all_in_one "no-adguard" ;;
      esac
    else
      run_all_in_one "${2:-no-adguard}"
    fi
    ;;
  -all-not)
    if [[ -z "${2:-}" ]] && [[ -t 0 ]]; then
      echo ""
      echo -e "${green}  Отмена «все в одном» — выбор пресета запуска контейнеров${plain}"
      echo -e "  ${blue}1.${plain} Пресет 1 (с adguard)"
      echo -e "  ${blue}2.${plain} Пресет 2 (без adguard, по умолчанию)"
      echo -n "Выберите пресет [1/2, по умолчанию 2]: "
      read -r preset_choice
      case "${preset_choice:-2}" in
        1) run_all_not "all" ;;
        2) run_all_not "no-adguard" ;;
        *) LOGE "Неверный выбор, используется пресет 2."; run_all_not "no-adguard" ;;
      esac
    else
      run_all_not "${2:-no-adguard}"
    fi
    ;;
  *)
    LOGE "Неизвестная команда: $cmd"
    usage
    exit 1
    ;;
esac
