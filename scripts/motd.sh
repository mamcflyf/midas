#!/usr/bin/env bash
# One-command installer: Distillium MOTD + MIDAS extension
set -Eeuo pipefail
BASE_URL='https://raw.githubusercontent.com/distillium/motd/main/install-motd.sh'
EXTRA_CONF=/etc/motd-midas.conf
EXTRA_SCRIPT=/etc/update-motd.d/01-midas-extra
SETTINGS=/usr/local/bin/motd-set
ORIGINAL=/usr/local/bin/motd-set-distillium
SELF=/usr/local/sbin/motd-midas-installer

[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
[[ -f /etc/debian_version ]] || { echo 'Debian/Ubuntu only' >&2; exit 1; }

if [[ ${1:-} == --uninstall-extension ]]; then
  if [[ -e "$ORIGINAL" ]]; then mv -f "$ORIGINAL" "$SETTINGS"; fi
  if [[ -f /opt/motd/midas-distillium-original.sh ]]; then cp -a /opt/motd/midas-distillium-original.sh /etc/update-motd.d/00-dist-motd; rm -f /opt/motd/midas-distillium-original.sh; fi
  rm -f "$EXTRA_SCRIPT" "$EXTRA_CONF" "$SELF" /usr/local/sbin/motd-safe-hostname /usr/local/sbin/motd-midas-translate
  echo 'Extension removed; original Distillium retained.'
  exit 0
fi

# Keep stdin available for interactive upstream installer even when invoked via curl | bash.
if [[ -r /dev/tty ]]; then
  exec 3</dev/tty
else
  exec 3</dev/null
fi

# Install upstream only if not already installed. No piping remote code directly to bash.
if [[ ! -x /etc/update-motd.d/00-dist-motd || ! -x "$SETTINGS" ]]; then
  command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
  tmp=$(mktemp)
  trap 'rm -f "${tmp:-}"' EXIT
  curl -fLSs --retry 2 --connect-timeout 10 --max-time 60 "$BASE_URL" -o "$tmp"
  bash -n "$tmp"
  echo 'Установка оригинального Distillium MOTD...'
  bash "$tmp" <&3
fi

[[ -x "$SETTINGS" || -e "$ORIGINAL" ]] || { echo 'Distillium motd-set not found' >&2; exit 1; }

if [[ ! -e "$EXTRA_CONF" ]]; then
cat > "$EXTRA_CONF" <<'CONFIG'
# MIDAS MOTD extension configuration
SERVER_LABEL=""
LANGUAGE="ru"
HOSTING_NAME=""
SHOW_IP=1
SHOW_HOSTING=1
SHOW_KERNEL=1
SHOW_UPDATES=1
SHOW_UFW=1
SHOW_EXTRA_CPU=1
SHOW_EXTRA_RAM=1
SHOW_DISK=1
CONFIG
chmod 600 "$EXTRA_CONF"
fi

cat > "$EXTRA_SCRIPT" <<'EXTRA'
#!/usr/bin/env bash
[[ -r /etc/motd-midas.conf ]] || exit 0
# Config is root-writable only. Shell-quote values when editing manually.
source /etc/motd-midas.conf
export LC_ALL=C
if [[ ${LANGUAGE:-ru} == ru ]]; then
  title="СВЕДЕНИЯ О СЕРВЕРЕ"; server_label="Сервер"; hosting_label="Хостер"; kernel_label="Ядро"; updates_label="Обновления"; disk_label="Диск"
else
  title="SERVER DETAILS"; server_label="Server"; hosting_label="Hosting"; kernel_label="Kernel"; updates_label="Updates"; disk_label="Disk"
fi
printf '\n\033[1;36m  ── %s ──\033[0m\n' "$title"
show() { printf '  %-12s %s\n' "$1" "$2"; }
show "$server_label" "${SERVER_LABEL:-$(hostname)}"
if [[ ${SHOW_IP:-1} == 1 ]]; then
  for fam in 4 6; do
    target=1.1.1.1; [[ $fam == 6 ]] && target=2606:4700:4700::1111
    addr=$(ip -"$fam" route get "$target" 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n1)
    show "IPv$fam" "${addr:-Unavailable}"
  done
fi
if [[ ${SHOW_HOSTING:-1} == 1 ]]; then
  hosting=${HOSTING_NAME:-}
  if [[ -z $hosting ]]; then
    cache=/var/cache/motd-midas-hosting
    if [[ ! -s $cache || -n $(find "$cache" -mmin +1440 -print 2>/dev/null) ]]; then
      result=$(curl -4fsS --connect-timeout 1 --max-time 2 https://ipinfo.io/org 2>/dev/null | head -c 120 || true)
      [[ -n $result ]] && printf '%s\n' "$result" > "$cache"
    fi
    hosting=$(cat "$cache" 2>/dev/null || true)
  fi
  show "$hosting_label" "${hosting:-Unknown}"
fi
[[ ${SHOW_KERNEL:-1} == 1 ]] && show "$kernel_label" "$(uname -r)"
if [[ ${SHOW_UPDATES_EXTRA:-0} == 1 ]]; then
  count=$(apt list --upgradable 2>/dev/null | awk 'NR>1 && /\[upgradable from:/ {n++} END {print n+0}')
  show "$updates_label" "$count (cached APT lists)"
fi
if [[ ${SHOW_UFW_EXTRA:-0} == 1 ]]; then
  if ! command -v ufw >/dev/null; then status='Not installed'
  elif ufw status 2>/dev/null | grep -q '^Status: active'; then status='ACTIVE'
  else status='INACTIVE'; fi
  if [[ ${LANGUAGE:-ru} == ru ]]; then case $status in ACTIVE) status='ВКЛЮЧЁН';; INACTIVE) status='ВЫКЛЮЧЕН';; 'Not installed') status='Не установлен';; esac; fi
  show 'UFW' "$status"
fi
if [[ ${SHOW_EXTRA_CPU:-1} == 1 ]]; then
  model=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)
  show 'CPU' "${model:-Unknown} ($(nproc 2>/dev/null || echo '?') vCPU)"
fi
if [[ ${SHOW_EXTRA_RAM:-1} == 1 ]]; then
  ram=$(free -h | awk '/^Mem:/ {print $3 " / " $2 " used; " $7 " available"}')
  show 'RAM' "${ram:-Unknown}"
fi
if [[ ${SHOW_DISK:-1} == 1 ]]; then
  disk=$(df -hP / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
  source_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
  parent=$(lsblk -no PKNAME "$source_dev" 2>/dev/null | head -n1 || true)
  [[ -n $parent ]] || parent=$(lsblk -no NAME "$source_dev" 2>/dev/null | head -n1 || true)
  model='Virtual / Unknown'; transport=''
  if [[ -n $parent && -b /dev/$parent ]]; then
    m=$(lsblk -dn -o MODEL "/dev/$parent" 2>/dev/null | xargs || true)
    [[ -n $m ]] && model=$m
    transport=$(lsblk -dn -o TRAN "/dev/$parent" 2>/dev/null | xargs || true)
  fi
  if [[ ${LANGUAGE:-ru} == ru ]]; then show 'Накопитель' "$model${transport:+ ($transport)}"; show 'Диск /' "${disk:-Неизвестно}"; else show 'Storage' "$model${transport:+ ($transport)}"; show 'Disk /' "${disk:-Unknown}"; fi
fi
EXTRA
chmod 755 "$EXTRA_SCRIPT"

# Safe hostname change helper, including persistent cloud-init policy.
cat > /usr/local/sbin/motd-safe-hostname <<'HOSTHELPER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Root required' >&2; exit 1; }
new=${1:-}
[[ $new =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || { echo 'Invalid hostname' >&2; exit 1; }
command -v hostnamectl >/dev/null || { echo 'hostnamectl is unavailable' >&2; exit 1; }
old=$(hostname)
[[ $old != "$new" ]] || exit 0
# Keep cloud-init from restoring the provider-assigned hostname on reboot.
cloud_config=/etc/cloud/cloud.cfg.d/99-zz-midas-hostname.cfg
cloud_enabled=0
if [[ -f /etc/cloud/cloud.cfg ]]; then
  cloud_enabled=1
fi
backup_dir=$(mktemp -d /root/motd-hostname-backup.XXXXXXXX)
cp -a /etc/hostname "$backup_dir/hostname" 2>/dev/null || true
cp -a /etc/hosts "$backup_dir/hosts"
if (( cloud_enabled )); then
  if [[ -e $cloud_config ]]; then
    cp -a "$cloud_config" "$backup_dir/cloud-config"
  else
    touch "$backup_dir/cloud-config-absent"
  fi
fi
rollback() {
  echo 'Hostname update failed; attempting rollback...' >&2
  cp -a "$backup_dir/hosts" /etc/hosts || true
  if [[ -f $backup_dir/hostname ]]; then cp -a "$backup_dir/hostname" /etc/hostname || true; fi
  if [[ -f $backup_dir/cloud-config ]]; then
    cp -a "$backup_dir/cloud-config" "$cloud_config" || true
  elif [[ -f $backup_dir/cloud-config-absent ]]; then
    rm -f "$cloud_config" || true
  fi
  hostnamectl set-hostname "$old" || true
}
trap rollback ERR
# Update only an existing Debian 127.0.1.1 record. Preserve aliases and comments.
if grep -Eq '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
  NEW_HOSTNAME="$new" OLD_HOSTNAME="$old" python3 - <<'PYHOST'
from pathlib import Path
import os
p=Path('/etc/hosts')
old=os.environ['OLD_HOSTNAME']; new=os.environ['NEW_HOSTNAME']
lines=[]
for line in p.read_text().splitlines(keepends=True):
    if line.split('#',1)[0].split()[:1] == ['127.0.1.1']:
        body, sep, comment = line.partition('#')
        fields=body.split()
        fields=[new if x==old else x for x in fields]
        if old not in body.split():
            fields.insert(1,new)
        # Remove duplicate host aliases while retaining other aliases.
        fields=list(dict.fromkeys(fields))
        line='\t'.join(fields)+((' #'+comment.rstrip('\n')) if sep else '')+'\n'
    lines.append(line)
p.write_text(''.join(lines))
PYHOST
fi
if (( cloud_enabled )); then
  mkdir -p /etc/cloud/cloud.cfg.d
  printf '# Managed by MIDAS MOTD hostname setup\npreserve_hostname: true\n' > "$cloud_config"
fi
hostnamectl set-hostname "$new"
[[ $(hostname) == "$new" ]] || { echo 'Hostname verification failed' >&2; false; }
trap - ERR
echo "Hostname changed: $old -> $new"
echo "Backup: $backup_dir"
if (( cloud_enabled )); then
  echo "cloud-init hostname preservation: $cloud_config"
fi
echo 'Reconnect SSH to update the shell prompt.'
HOSTHELPER
chmod 700 /usr/local/sbin/motd-safe-hostname

# Preserve upstream settings menu and add a wrapper. Idempotent on reruns.
if [[ ! -e "$ORIGINAL" ]]; then mv "$SETTINGS" "$ORIGINAL"; fi
cat > "$SETTINGS" <<'MENU'
#!/usr/bin/env bash
set -u
CONF=/etc/motd-midas.conf
BASE=/etc/dist-motd.conf
[[ $EUID -eq 0 ]] || { echo 'Запустите от root / Run as root'; exit 1; }
[[ -r /dev/tty ]] || { echo 'Требуется интерактивный терминал / TTY required'; exit 1; }
read_setting() { source "$CONF"; [[ -f "$BASE" ]] && source "$BASE"; }
write_setting() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  awk -v k="$key" -v v="$value" 'BEGIN {done=0} index($0,k"=")==1 {print k"="v;done=1;next} {print} END {if (!done) print k"="v}' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}
set_string() {
  local key=$1 label=$2 val quoted
  printf '%s: ' "$label" > /dev/tty
  IFS= read -r val </dev/tty || return
  printf -v quoted '%q' "$val"
  write_setting "$CONF" "$key" "$quoted"
}
toggle() {
  local file=$1 key=$2 current=$3
  if [[ $current == true ]]; then write_setting "$file" "$key" false
  elif [[ $current == false ]]; then write_setting "$file" "$key" true
  elif [[ $current == 1 ]]; then write_setting "$file" "$key" 0
  else write_setting "$file" "$key" 1; fi
}
rename_host() {
  local name old answer
  old=$(hostname)
  printf 'Текущее имя / Current hostname: %s\nНовое имя / New hostname: ' "$old" > /dev/tty
  IFS= read -r name </dev/tty || return
  [[ -n $name && $name != "$old" ]] || return 0
  echo 'Внимание: проверьте зависимости сертификатов, мониторинга и приложений от старого hostname.' > /dev/tty
  printf 'Подтвердите изменение / Type YES: ' > /dev/tty
  IFS= read -r answer </dev/tty || return
  [[ $answer == YES ]] && /usr/local/sbin/motd-safe-hostname "$name"
}
while :; do
  read_setting
  if [[ ${LANGUAGE:-ru} == ru ]]; then
    cat > /dev/tty <<EOF

════════════ НАСТРОЙКИ MOTD ════════════
 1) Язык: Русский
 2) Цветовая тема: ${COLOR_THEME:-dark}
 3) Логотип: ${SHOW_LOGO:-true}
 4) CPU: ${SHOW_CPU:-true}
 5) RAM: ${SHOW_MEM:-true}
 6) Сеть: ${SHOW_NET:-false}
 7) Docker: ${SHOW_DOCKER:-true}
 8) Статус Docker: ${SHOW_DOCKER_STATUS:-true}
 9) Список контейнеров: ${SHOW_DOCKER_RUNNING_LIST:-false}
10) Брандмауэр: ${SHOW_FIREWALL:-true}
11) Правила брандмауэра: ${SHOW_FIREWALL_RULES:-false}
12) Обновления: ${SHOW_UPDATES:-true}
13) Безопасность: ${SHOW_SECURITY:-false}
14) Состояние служб: ${SERVICES_STATUS_ENABLED:-false}

──────────── СЕРВЕР И ЖЕЛЕЗО ────────────
15) Изменить настоящее имя машины: $(hostname)
16) Название сервера: ${SERVER_LABEL:-авто}
17) Название хостера: ${HOSTING_NAME:-авто}
18) IPv4 и IPv6: ${SHOW_IP:-1}
19) Хостер: ${SHOW_HOSTING:-1}
20) Ядро: ${SHOW_KERNEL:-1}
21) Подробная информация CPU: ${SHOW_EXTRA_CPU:-1}
22) Подробная информация RAM: ${SHOW_EXTRA_RAM:-1}
23) Модель и заполнение диска: ${SHOW_DISK:-1}
24) Просмотр MOTD
 0) Выход
EOF
  else
    cat > /dev/tty <<EOF

════════════ MOTD SETTINGS ════════════
 1) Language: English
 2) Color theme: ${COLOR_THEME:-dark}
 3) Logo: ${SHOW_LOGO:-true}
 4) CPU: ${SHOW_CPU:-true}
 5) RAM: ${SHOW_MEM:-true}
 6) Network: ${SHOW_NET:-false}
 7) Docker: ${SHOW_DOCKER:-true}
 8) Docker status: ${SHOW_DOCKER_STATUS:-true}
 9) Running containers: ${SHOW_DOCKER_RUNNING_LIST:-false}
10) Firewall: ${SHOW_FIREWALL:-true}
11) Firewall rules: ${SHOW_FIREWALL_RULES:-false}
12) Updates: ${SHOW_UPDATES:-true}
13) Security: ${SHOW_SECURITY:-false}
14) Services: ${SERVICES_STATUS_ENABLED:-false}

──────────── SERVER & HARDWARE ────────────
15) Change Linux hostname: $(hostname)
16) Server display name: ${SERVER_LABEL:-auto}
17) Hosting name: ${HOSTING_NAME:-auto}
18) IPv4 and IPv6: ${SHOW_IP:-1}
19) Hosting: ${SHOW_HOSTING:-1}
20) Kernel: ${SHOW_KERNEL:-1}
21) Detailed CPU: ${SHOW_EXTRA_CPU:-1}
22) Detailed RAM: ${SHOW_EXTRA_RAM:-1}
23) Disk model and usage: ${SHOW_DISK:-1}
24) Preview MOTD
 0) Exit
EOF
  fi
  printf '> ' > /dev/tty
  IFS= read -r choice </dev/tty || exit 0
  case "$choice" in
    0) exit 0 ;;
    1) if [[ ${LANGUAGE:-ru} == ru ]]; then lang=en; else lang=ru; fi
       write_setting "$CONF" LANGUAGE "$lang"; write_setting "$BASE" MOTDSET_LANG "$lang"
       /usr/local/sbin/motd-midas-translate "$lang" ;;
    2) printf '1) Dark / Тёмная  2) Light / Светлая  3) Auto / Авто: ' > /dev/tty
       read -r c </dev/tty; case "$c" in 1) theme=dark;;2) theme=light;;3) theme=auto;;*) continue;;esac
       write_setting "$BASE" COLOR_THEME "$theme" ;;
    3|4|5|6|7|8|9|10|11|12|13|14)
       case "$choice" in
       3) key=SHOW_LOGO;;4) key=SHOW_CPU;;5) key=SHOW_MEM;;6) key=SHOW_NET;;
       7) key=SHOW_DOCKER;;8) key=SHOW_DOCKER_STATUS;;9) key=SHOW_DOCKER_RUNNING_LIST;;
       10) key=SHOW_FIREWALL;;11) key=SHOW_FIREWALL_RULES;;12) key=SHOW_UPDATES;;
       13) key=SHOW_SECURITY;;14) key=SERVICES_STATUS_ENABLED;; esac
       eval 'current=${'"$key"':-false}'; toggle "$BASE" "$key" "$current" ;;
    15) rename_host ;;
    16) set_string SERVER_LABEL 'Имя сервера / Server label (Enter = hostname)' ;;
    17) set_string HOSTING_NAME 'Хостер / Hosting name (Enter = auto)' ;;
    18|19|20|21|22|23)
       case "$choice" in 18) key=SHOW_IP;;19) key=SHOW_HOSTING;;20) key=SHOW_KERNEL;;
       21) key=SHOW_EXTRA_CPU;;22) key=SHOW_EXTRA_RAM;;23) key=SHOW_DISK;;esac
       eval 'current=${'"$key"':-1}'; toggle "$CONF" "$key" "$current" ;;
    24) /usr/local/bin/motd; [[ -x /etc/update-motd.d/01-midas-extra ]] && /etc/update-motd.d/01-midas-extra ;;
    *) echo 'Неверный выбор / Invalid choice' > /dev/tty ;;
  esac
done
MENU
chmod 755 "$SETTINGS"

# Translate original Distillium MOTD output without changing its functionality.
cat > /usr/local/sbin/motd-midas-translate <<'TRANSLATE'
#!/usr/bin/env python3
import pathlib, sys, shutil
lang = sys.argv[1] if len(sys.argv)>1 else 'ru'
if lang not in ('ru','en'): sys.exit('Unknown language')
p = pathlib.Path('/etc/update-motd.d/00-dist-motd')
backup = pathlib.Path('/opt/motd/midas-distillium-original.sh')
if not p.exists(): sys.exit(0)
backup.parent.mkdir(parents=True, exist_ok=True)
if not backup.exists(): shutil.copy2(p, backup)
s = backup.read_text()
# Only replace visible, quoted English labels, not keywords used by shell logic.
replacements = {
'• Session Details':'• Сведения о сеансе',
'• System Details':'• Сведения о системе',
'• RAM & Disk':'• Память и диск',
'• Network':'• Сеть',
'• Firewall':'• Брандмауэр',
'• Updates Available':'• Доступные обновления',
'• Security':'• Безопасность',
'"User:"':'"Пользователь:"',
'"Last login:"':'"Последний вход:"',
'"Uptime:"':'"Время работы:"',
'"Hostname:"':'"Имя машины:"',
'"External IP (v4):"':'"Внешний IPv4:"',
'"External IP (v6):"':'"Внешний IPv6:"',
'"Kernel:"':'"Ядро:"',
'"Model:"':'"Модель:"',
'"Usage:"':'"Загрузка:"',
'"Load average:"':'"Средняя нагрузка:"',
'"Disk:"':'"Диск:"',
'"Interface:"':'"Интерфейс:"',
'"Received:"':'"Получено:"',
'"Transmitted:"':'"Отправлено:"',
'"Network:"':'"Сеть:"',
'"UFW Status:"':'"Статус UFW:"',
'"Rules:"':'"Правила:"',
'"Containers:"':'"Контейнеры:"',
'"Running Containers:"':'"Запущенные контейнеры:"',
'"Total updates:"':'"Всего обновлений:"',
'"Security updates:"':'"Обновления безопасности:"',
'"Status:"':'"Состояние:"',
'"Updates:"':'"Обновления:"',
'"System is up to date"':'"Система обновлена"',
'"apt not available"':'"APT недоступен"',
'"not installed"':'"не установлен"',
'"info disabled by configuration"':'"информация отключена в настройках"',
'"Interface not found"':'"Интерфейс не найден"',
'"Run \'sudo apt upgrade\' to install updates"':'"Для установки обновлений: sudo apt upgrade"',
}
if lang == 'ru':
    for a,b in replacements.items(): s=s.replace(a,b)
p.write_text(s)
p.chmod(0o755)
TRANSLATE
chmod 755 /usr/local/sbin/motd-midas-translate
# Respect existing language choice on reruns.
source "$EXTRA_CONF"
if [[ -f /etc/dist-motd.conf ]]; then
  if grep -q '^MOTDSET_LANG=' /etc/dist-motd.conf; then
    sed -i "s/^MOTDSET_LANG=.*/MOTDSET_LANG=${LANGUAGE:-ru}/" /etc/dist-motd.conf
  else
    printf 'MOTDSET_LANG=%s\\n' "${LANGUAGE:-ru}" >> /etc/dist-motd.conf
  fi
fi
/usr/local/sbin/motd-midas-translate "${LANGUAGE:-ru}"

# Interactive first-run setup, including real Linux hostname and provider name.
# Read from the terminal: curl | bash consumes stdin otherwise.
if [[ -t 3 ]]; then
  printf '\n\033[1;36m=== MIDAS MOTD: ПЕРВОНАЧАЛЬНАЯ НАСТРОЙКА ===\033[0m\n'
  printf 'Текущее имя машины: %s\n' "$(hostname)"
  printf 'Новое имя машины (Enter = оставить): '
  IFS= read -r new_hostname <&3 || new_hostname=''
  if [[ -n $new_hostname ]]; then
    echo 'ВНИМАНИЕ: смена имени может повлиять на мониторинг, TLS и сервисы, зависящие от hostname.'
    printf 'Введите YES для подтверждения: '
    IFS= read -r confirmation <&3 || confirmation=''
    if [[ $confirmation == YES ]]; then
      /usr/local/sbin/motd-safe-hostname "$new_hostname" || echo 'Hostname change failed; inspect the messages above.' >&2
    else
      echo 'Имя машины не изменено.'
    fi
  fi
  printf 'Название хостера (Enter = определить автоматически): '
  IFS= read -r provider_name <&3 || provider_name=''
  if [[ -n $provider_name ]]; then
    printf -v quoted_provider '%q' "$provider_name"
    tmpconf=$(mktemp)
    awk -v v="$quoted_provider" '/^HOSTING_NAME=/{print "HOSTING_NAME=" v;next}{print}' "$EXTRA_CONF" > "$tmpconf"
    cat "$tmpconf" > "$EXTRA_CONF"
    rm -f "$tmpconf"
    chmod 600 "$EXTRA_CONF"
  fi
  printf 'Название сервера в MOTD (Enter = использовать hostname): '
  IFS= read -r server_label <&3 || server_label=''
  if [[ -n $server_label ]]; then
    printf -v quoted_label '%q' "$server_label"
    tmpconf=$(mktemp)
    awk -v v="$quoted_label" '/^SERVER_LABEL=/{print "SERVER_LABEL=" v;next}{print}' "$EXTRA_CONF" > "$tmpconf"
    cat "$tmpconf" > "$EXTRA_CONF"
    rm -f "$tmpconf"
    chmod 600 "$EXTRA_CONF"
  fi
else
  echo 'Терминал недоступен: первичная настройка пропущена. Запустите motd-set.'
fi
printf '\nDistillium + MIDAS установлен. Команды: motd-set, motd\n' 
printf 'Удаление расширения: bash install-motd.sh --uninstall-extension\n'
