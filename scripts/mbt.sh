#!/bin/bash

# =============================================================================
# MBT — единая точка входа и все настройки
# Без параметров: интерактивное меню по цифрам
#
# С параметром:
#   -r, -restart              Перезапуск бота (make r)
#   -s, -swap                 Создать и включить swap (1.5 GB)
#   -suc, -stop-unwanted-containers   Остановить ненужные Docker-контейнеры
#   -crontab-r, -crontab-reboot       Добавить в crontab автоперезапуск бота при загрузке
#   -crontab-suc, -crontab-stop-unwanted-containers          Добавить в crontab остановку контейнеров после загрузки
#   -bbr                     Подменю BBR (вкл/выкл)
#   -ipv6                    Подменю IPv6 (вкл/выкл)
#   -f2b, -fail2ban          Подменю Fail2ban (защита SSH)
#   -sub                     Внедрить verifyUser в бота (получать подписку от бота)
#   -all                     Все в одном (swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban)
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
  echo -e "  ${green}-crontab-reboot${plain}, ${green}-crontab-r${plain}   Добавить в crontab автоперезапуск бота при загрузке"
  echo -e "  ${green}-crontab-suc${plain}, ${green}-crontab-stop-unwanted-containers${plain}   Добавить в crontab остановку контейнеров после загрузки"
  echo -e "  ${green}-bbr${plain}                     Подменю BBR (вкл/выкл)"
  echo -e "  ${green}-ipv6${plain}                    Подменю IPv6 (вкл/выкл)"
  echo -e "  ${green}-fail2ban${plain}, ${green}-f2b${plain}          Подменю Fail2ban (защита SSH)"
  echo -e "  ${green}-sub${plain}                     Внедрить verifyUser в бота (получать подписку от бота)"
  echo -e "  ${green}-all${plain}                     Все в одном (swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban)"
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
CRONTAB_REBOOT_SUC="@reboot (sleep 300 && cd $cur_dir && ./$SCRIPT_NAME -suc)"

crontab_has_stop_containers() {
  crontab -l 2>/dev/null | grep -qF "./$SCRIPT_NAME -suc"
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
  crontab -l 2>/dev/null | grep -vF "./$SCRIPT_NAME -suc" | crontab -
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

# --- Sub: внедрить verifyUser в бота (получать подписку от бота) ---

run_sub() {
  local app_dir="$VPNBOT_DIR/app"
  local bot_php="$app_dir/bot.php"
  local snippet_tmp
  snippet_tmp=$(mktemp)
  trap 'rm -f "$snippet_tmp"' RETURN

  if [[ ! -f "$bot_php" ]]; then
    LOGE "Не найден: $bot_php (VPNBOT_DIR=$VPNBOT_DIR)"
    return 1
  fi

  if grep -q "you are not authorized" "$bot_php"; then
    LOGI "Заменяю комментарий в auth() на \$this->verifyUser(); ..."
    sed -i '/you are not authorized/s/.*/        $this->verifyUser();/' "$bot_php"
  fi
  if grep -q '\$this->verifyUser();' "$bot_php" && ! grep -q "preg_match.*verifySub" "$bot_php"; then
    LOGI "Правка auth(): разрешаю callback /verifySub (иначе при нажатии кнопок шло бы новое сообщение) ..."
    awk '
      /^\s+\$this->verifyUser\(\);?\s*$/ {
        if (match($0, /^[ \t]+/)) { sp = substr($0, RSTART, RLENGTH) } else { sp = "        " }
        print sp "if (preg_match('\''~^/verifySub~'\'', $this->input['\''callback'\''] ?? '\'''\'')) {"
        print sp "} else {"
        print sp "    $this->verifyUser();"
        print sp "    exit;"
        print sp "}"
        done = 1
        next
      }
      done && /^\s+exit;\s*$/ { done = 0; next }
      { print }
    ' "$bot_php" > "$bot_php.awked" && mv "$bot_php.awked" "$bot_php"
  fi
  if ! grep -q "case preg_match.*verifySub" "$bot_php"; then
    LOGI "Добавляю обработчик callback /verifySub в action() ..."
    case_line=$(grep -n "case preg_match.*menu.*message" "$bot_php" | head -1 | cut -d: -f1)
    if [[ -n "$case_line" ]]; then
      {
        head -n $((case_line - 1)) "$bot_php"
        echo "            case preg_match('~^/verifySub(?:\s+(?P<arg>.+))?\$~', \$this->input['callback'], \$m):"
        echo "                \$this->verifyUserCallback(\$m['arg'] ?? 'list');"
        echo "                break;"
        tail -n +"$case_line" "$bot_php"
      } > "$bot_php.new" && mv "$bot_php.new" "$bot_php"
    fi
  fi

  cat << 'VERIFYUSER_SNIPPET_END' > "$snippet_tmp"
    private function verifyUserGetFoundIndexes(): array
    {
        $clients = $this->getXray()['inbounds'][0]['settings']['clients'] ?? [];
        $foundIndexes = [];
        foreach ($clients as $i => $user) {
            if (isset($user['email']) && preg_match('/\[tg_(\d+)]/i', $user['email'], $m) && (string)$m[1] === (string)$this->input['from']) {
                $foundIndexes[] = $i;
            }
        }
        return $foundIndexes;
    }

    private function verifyUserTrafficLine(int $clientIndex): string
    {
        try {
            $st = $this->getXrayStats();
            if (empty($st['users'][$clientIndex])) {
                return '';
            }
            $u = $st['users'][$clientIndex];
            $down = ($u['global']['download'] ?? 0) + ($u['session']['download'] ?? 0);
            $up   = ($u['global']['upload'] ?? 0) + ($u['session']['upload'] ?? 0);
            return "📊 <b>Трафик:</b> ↓ " . $this->getBytes($down) . "  ·  ↑ " . $this->getBytes($up);
        } catch (\Throwable $e) {
            return '';
        }
    }

    private function verifyUserConfigText(int $index): string
    {
        $foundIndexes = $this->verifyUserGetFoundIndexes();
        if (!isset($foundIndexes[$index])) {
            return '';
        }
        $esc = fn(string $s) => htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $clients = $this->getXray()['inbounds'][0]['settings']['clients'] ?? [];
        $clientIdx = $foundIndexes[$index];
        $c = $clients[$clientIdx];
        $email = $c['email'];
        $pac = $this->getPacConf();
        $domain = $this->getDomain($pac['transport'] != 'Reality');
        $scheme = empty($this->nginxGetTypeCert()) ? 'http' : 'https';
        $hash = $this->getHashBot();
        $siPayload = base64_encode(serialize(['h' => $hash, 't' => 'si', 's' => $c['id']]));
        $si = "{$scheme}://{$domain}/pac{$hash}/{$siPayload}";
        $importUrl = "{$scheme}://{$domain}/pac{$hash}?t=si&r=si&s={$c['id']}#" . rawurlencode($email);
        $windowsUrl = "{$scheme}://{$domain}/pac{$hash}?t=si&r=w&s={$c['id']}";
        $emailLower = strtolower($email);
        $isOpenWrt = str_contains($emailLower, '[openwrt]');
        $isWindows = str_contains($emailLower, '[windows]');
        $isTablet = str_contains($emailLower, '[tablet]');
        $isMac = str_contains($emailLower, '[mac]');
        $cleanName = preg_replace('/^\[tg_\d+]\_?/', '', $email) ?: "Профиль " . ($index + 1);
        $trafficLine = $this->verifyUserTrafficLine($clientIdx);
        $lines = [];
        $lines[] = "👤 <b>Профиль:</b> <code>{$esc($cleanName)}</code>";
        if ($trafficLine !== '') {
            $lines[] = $trafficLine;
        }
        $lines[] = "";
        $lines[] = "━━━ <b>Инструкция по устройству</b> ━━━";
        if ($isOpenWrt) {
            $lines[] = "📡 <b>Роутер (OpenWRT)</b>";
            $lines[] = "• Установите: <a href=\"https://github.com/ang3el7z/luci-app-singbox-ui\">luci-app-singbox-ui</a>";
            $lines[] = "• Конфиг-сервер:";
            $lines[] = "<code>{$esc($si)}</code>";
        } elseif ($isWindows) {
            $lines[] = "🖥 <b>Windows 10/11</b>";
            $lines[] = "• Скачать: <a href=\"{$esc($windowsUrl)}\">sing-box для Windows</a>";
            $lines[] = "• Распаковать в <code>C:\\serviceBot</code> (путь только латиницей)";
            $lines[] = "• Запустить <code>install</code>, затем <code>start</code>";
            $lines[] = "• Проверка: <code>status</code>";
        } elseif ($isTablet) {
            $lines[] = "📱 <b>Планшет (Android / iOS)</b>";
            $lines[] = "• Установить sing-box: Play Store / App Store";
            $lines[] = "• Импорт: <a href=\"{$esc($importUrl)}\">import://sing-box</a>";
            $lines[] = "• Import → Create → Dashboard → Start";
        } elseif ($isMac) {
            $lines[] = "💻 <b>Mac</b>";
            $lines[] = "• Установить sing-box (App Store)";
            $lines[] = "• Импорт: <a href=\"{$esc($importUrl)}\">import://sing-box</a>";
            $lines[] = "• Import → Create → Dashboard → Start";
        } else {
            $lines[] = "📱 <b>Телефон (Android / iOS)</b>";
            $lines[] = "• Установить sing-box: Play Store / App Store";
            $lines[] = "• Импорт: <a href=\"{$esc($importUrl)}\">import://sing-box</a>";
            $lines[] = "• Import → Create → Dashboard → Start";
        }
        $lines[] = "";
        $lines[] = "🔒 <b>Ограничения</b>";
        $lines[] = "• Один конфиг — одно устройство";
        $lines[] = "• Передача конфига посторонним — <b>бан навсегда</b>";
        $lines[] = "• Не использовать на нескольких устройствах одновременно";
        $lines[] = "";
        $lines[] = "⚠️ Нажмите кнопку <b>Обновить</b> ниже для актуальной конфигурации.";
        return implode("\n", $lines);
    }

    private function verifyUserListData(): array
    {
        $foundIndexes = $this->verifyUserGetFoundIndexes();
        if (empty($foundIndexes)) {
            return ['text' => '', 'keyboard' => []];
        }
        $clients = $this->getXray()['inbounds'][0]['settings']['clients'] ?? [];
        $rows = [];
        foreach ($foundIndexes as $i => $idx) {
            $email = $clients[$idx]['email'] ?? '';
            $cleanName = preg_replace('/^\[tg_\d+]\_?/', '', $email) ?: "Профиль " . ($i + 1);
            $rows[] = [['text' => $cleanName, 'callback_data' => "/verifySub $i"]];
        }
        $header = "📋 <b>Ваши профили</b>\n\nВыберите профиль — откроется инструкция и ссылки для подключения.";
        return ['text' => $header, 'keyboard' => $rows];
    }

    public function verifyUser(): void
    {
        $foundIndexes = $this->verifyUserGetFoundIndexes();
        if (empty($foundIndexes)) {
            return;
        }
        try {
            if (count($foundIndexes) === 1) {
                $text = $this->verifyUserConfigText(0);
                $keyboard = [[['text' => "🔄 Обновить", 'callback_data' => '/verifySub refresh']]];
                $this->send($this->input['chat'], $text, 0, $keyboard, false, 'HTML', false, true);
            } else {
                $list = $this->verifyUserListData();
                $this->send($this->input['chat'], $list['text'], 0, $list['keyboard'], false, 'HTML', false, true);
            }
        } catch (\Throwable $e) {
            $this->send($this->input['chat'], "verifyUser: " . $e->getMessage(), $this->input['message_id']);
        }
    }

    public function verifyUserCallback(?string $arg): void
    {
        $foundIndexes = $this->verifyUserGetFoundIndexes();
        if (empty($foundIndexes)) {
            $this->answer($this->input['callback_id'], 'Нет конфигов.');
            return;
        }
        $chat = $this->input['chat'];
        $messageId = $this->input['message_id'];
        $arg = trim((string)$arg);
        if ($arg === 'list' || $arg === '') {
            $list = $this->verifyUserListData();
            $this->update($chat, $messageId, $list['text'], $list['keyboard']);
            $this->answer($this->input['callback_id']);
            return;
        }
        if (preg_match('/^refresh(?:\s+(\d+))?$/', $arg, $m)) {
            $index = isset($m[1]) ? (int)$m[1] : 0;
            if (!isset($foundIndexes[$index])) {
                $index = 0;
            }
        } elseif (ctype_digit($arg)) {
            $index = (int)$arg;
            if (!isset($foundIndexes[$index])) {
                $index = 0;
            }
        } else {
            return;
        }
        $text = $this->verifyUserConfigText($index);
        $keyboard = [];
        if (count($foundIndexes) > 1) {
            $keyboard[] = [['text' => "← Назад", 'callback_data' => '/verifySub list'], ['text' => "🔄 Обновить", 'callback_data' => "/verifySub refresh $index"]];
        } else {
            $keyboard[] = [['text' => "🔄 Обновить", 'callback_data' => '/verifySub refresh']];
        }
        $this->update($chat, $messageId, $text, $keyboard);
        $this->answer($this->input['callback_id']);
    }
VERIFYUSER_SNIPPET_END

  if ! grep -q "function verifyUser()" "$bot_php"; then
    LOGI "Вставляю методы verifyUser и verifyUserCallback после auth() ..."
    auth_line=$(grep -n "public function auth()" "$bot_php" | head -1 | cut -d: -f1)
    if [[ -z "$auth_line" ]]; then
      LOGE "В bot.php не найдена функция public function auth()."
      return 1
    fi
    next_func_line=$(awk -v start="$auth_line" 'NR > start && /^[[:space:]]*public function / { print NR; exit }' "$bot_php")
    if [[ -z "$next_func_line" ]]; then
      LOGE "Не найден конец auth() (следующая public function)."
      return 1
    fi
    {
      head -n $((next_func_line - 1)) "$bot_php"
      cat "$snippet_tmp"
      echo ""
      tail -n +"$next_func_line" "$bot_php"
    } > "$bot_php.new" && mv "$bot_php.new" "$bot_php"
  elif ! grep -q "verifyUserCallback" "$bot_php"; then
    LOGI "Обновляю старый блок verifyUser (кнопка Обновить будет редактировать сообщение, а не отправлять новое) ..."
    start_line=$(grep -n "private function verifyUserGetFoundIndexes\|public function verifyUser()" "$bot_php" | head -1 | cut -d: -f1)
    next_method_line=$(awk -v start="$start_line" 'NR > start && /^    (public|private) function / { print NR; exit }' "$bot_php")
    if [[ -n "$start_line" && -n "$next_method_line" ]]; then
      end_line=$((next_method_line - 1))
      {
        head -n $((start_line - 1)) "$bot_php"
        cat "$snippet_tmp"
        echo ""
        tail -n +$((end_line + 1)) "$bot_php"
      } > "$bot_php.new" && mv "$bot_php.new" "$bot_php"
      LOGI "Блок verifyUser заменён на новую версию."
    else
      LOGE "Не удалось найти границы блока verifyUser для замены."
    fi
  else
    LOGD "Методы verifyUser/verifyUserCallback уже есть в bot.php."
  fi

  LOGI "Sub (verifyUser) применён. Перезапустите бота при необходимости (п. 1)."
}

# --- Все в одном ---

run_all_in_one() {
  check_root
  export RUN_ALL_IN_ONE=1
  LOGI "Все в одном: swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban..."
  run_swap
  LOGI "[1/7] Swap готов."
  run_stop_containers
  LOGI "[2/7] Контейнеры обработаны."
  crontab_add_reboot_restart
  LOGI "[3/7] Автозапуск бота добавлен в crontab."
  crontab_add_stop_containers
  LOGI "[4/7] Остановка контейнеров после загрузки добавлена в crontab."
  enable_bbr
  LOGI "[5/7] BBR включён."
  disable_ipv6
  LOGI "[6/7] IPv6 отключён."
  install_fail2ban_ssh
  LOGI "[7/7] Fail2ban включён."
  unset RUN_ALL_IN_ONE
  LOGI "Все в одном выполнено."
  before_show_menu
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
    echo -e "  ${blue}2.${plain} Создать swap 1.5 GB"
    echo -e "  ${blue}3.${plain} Остановить ненужные Docker-контейнеры"
    echo -e "  ${blue}4.${plain} Автоперезапуск бота при загрузке (вкл/выкл)"
    echo -e "  ${blue}5.${plain} Остановка контейнеров после загрузки (вкл/выкл)"
    echo -e "  ${blue}6.${plain} BBR (вкл/выкл)"
    echo -e "  ${blue}7.${plain} IPv6 (вкл/выкл)"
    echo -e "  ${blue}8.${plain} Fail2ban (защита SSH)"
    echo -e "  ${blue}9.${plain}  Все в одном (swap, контейнеры, crontab, BBR, IPv6 выкл, Fail2ban)"
    echo -e "  ${blue}10.${plain} Получать подписку от бота"
    echo -e "  ${blue}0.${plain}  Выход"
    echo -e "${green}═══════════════════════════════════════${plain}"
    echo -n "Выберите действие [0-10]: "
    read -r choice
    case "$choice" in
      1) run_restart; prompt_back_or_exit || exit 0 ;;
      2) run_swap; prompt_back_or_exit || exit 0 ;;
      3) run_stop_containers; prompt_back_or_exit || exit 0 ;;
      4) crontab_menu_reboot_restart ;;
      5) crontab_menu_stop_containers ;;
      6) bbr_menu ;;
      7) ipv6_menu ;;
      8) f2b_menu ;;
      9) run_all_in_one ;;
      10) run_sub; prompt_back_or_exit || exit 0 ;;
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
  -s|swap)
    run_swap
    ;;
  -suc|-stop-unwanted-containers)
    run_stop_containers
    ;;
  -crontab-r|-crontab-reboot)
    crontab_add_reboot_restart
    ;;
  -crontab-suc|-crontab-stop-unwanted-containers)
    crontab_add_stop_containers
    ;;
  -bbr)
    bbr_menu
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
  -all)
    run_all_in_one
    ;;
  *)
    LOGE "Неизвестная команда: $cmd"
    usage
    exit 1
    ;;
esac
