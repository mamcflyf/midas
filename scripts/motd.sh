#!/usr/bin/env bash
# MIDAS MOTD - self-contained Debian/Ubuntu installer (MIT)
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root / Запустите от root' >&2; exit 1; }
[[ -f /etc/debian_version ]] || { echo 'Debian/Ubuntu only' >&2; exit 1; }
if ! command -v whiptail >/dev/null 2>&1 && ! command -v dialog >/dev/null 2>&1; then
  echo 'Installing whiptail for interactive menu (maximum 60 seconds)...'
  DEBIAN_FRONTEND=noninteractive timeout 30 apt-get install -y -qq whiptail >/dev/null 2>&1 || echo 'whiptail unavailable: text menu fallback'
fi
BASE=/opt/midas-motd
CFG=/etc/midas-motd.conf
MOTD=/etc/update-motd.d/00-midas
BACK=$BASE/backup
mkdir -p "$BASE" "$BACK"
if [[ ! -f $BASE/installed ]]; then
  for f in /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/00-dist-motd /usr/local/bin/motd /usr/local/bin/motd-set; do
    [[ ! -e $f ]] || { mkdir -p "$BACK$(dirname "$f")"; cp -a "$f" "$BACK$f"; }
  done
fi
cat > "$BASE/lib.sh" <<'LIB'
#!/usr/bin/env bash
CFG=/etc/midas-motd.conf
# Only root-controlled configuration is sourced.
LANGUAGE=ru; THEME=cyan; SERVER_LABEL=''; HOSTING_NAME=''
SHOW_IP4=1; SHOW_IP6=1; SHOW_HOSTING=1; SHOW_KERNEL=1; SHOW_UPDATES=1
SHOW_UFW=1; SHOW_CPU=1; SHOW_RAM=1; SHOW_DISK=1; SHOW_DOCKER=1
SHOW_UPTIME=1; SHOW_LOAD=1; SHOW_OS=1; SHOW_NET=1; SHOW_UFW_RULES=1; SHOW_LASTLOGIN=0
[[ ! -r $CFG ]] || source "$CFG"
trn() { if [[ $LANGUAGE == ru ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
color() { case $THEME in green) printf '\033[1;32m';; purple) printf '\033[1;35m';; blue) printf '\033[1;34m';; none) printf '';; *) printf '\033[1;36m';; esac; }
reset() { printf '\033[0m'; }
line() { printf '  %-17s %s\n' "$1" "$2"; }
heading() { printf '\n'; color; printf '  ── %s ──────────────────────────────\n' "$1"; reset; }
flag() { [[ ${!1:-0} == 1 ]]; }
# The external lookup is done by a cache refresh command, never on SSH login.
provider() { [[ -n $HOSTING_NAME ]] && printf '%s' "$HOSTING_NAME" || { [[ ! -s /var/cache/midas-motd-provider ]] || head -n1 /var/cache/midas-motd-provider; }; }
LIB
cat > "$BASE/render.sh" <<'RENDER'
#!/usr/bin/env bash
set -u
source /opt/midas-motd/lib.sh
export LC_ALL=C.UTF-8
if [[ $THEME == none ]]; then BLUE=''; WHITE=''; GREEN=''; PINK=''; ORANGE=''; RESET=''
else
 BLUE=$'\033[1;34m'; WHITE=$'\033[1;37m'; GREEN=$'\033[0;32m'
 PINK=$'\033[1;35m'; ORANGE=$'\033[1;33m'; RESET=$'\033[0m'
fi
# Distillium-style fixed columns and progress bars
# Width-aware labels: UTF-8 Cyrillic is multi-byte, but each letter is one terminal cell.
label() { local text=$1; printf '%b%s%b' "$BLUE" "$text" "$RESET"; local pad=$((22-${#text})); ((pad<1)) && pad=1; printf '%*s' "$pad" ''; }
field() { label "$1"; printf '%b%s%b\n' "$2" "$3" "$RESET"; }
section() { printf '\n%b• %s%b\n' "$WHITE" "$1" "$RESET"; }
bar() {
 local used=${1:-0} total=${2:-0} width=30 filled=0 pct=0 i
 if ((total>0)); then pct=$((used*100/total)); filled=$((pct*width/100)); fi
 ((pct>100)) && pct=100
 printf '%b[' "$BLUE"
 for ((i=0;i<width;i++)); do
  if ((i<filled)); then printf '%b=' "$GREEN"; else printf '%b-' "$BLUE"; fi
 done
 printf '%b] %b%s%%%b' "$BLUE" "$GREEN" "$pct" "$RESET"
}
human_bytes() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || printf '%s B' "${1:-0}"; }
printf '%bMessage Of The Day by MIDAS MOTD%b\n' "$WHITE" "$RESET"
printf '%b====================================%b\n' "$WHITE" "$RESET"
section "$(trn 'Сведения о сеансе' 'Session Details')"
field "$(trn 'Пользователь:' 'User:')" "$ORANGE" "$(id -un)"
field "$(trn 'Имя сервера:' 'Server:')" "$GREEN" "${SERVER_LABEL:-$(hostname)}"
if flag SHOW_UPTIME; then field "$(trn 'Время работы:' 'Uptime:')" "$GREEN" "$(uptime -p 2>/dev/null | sed 's/^up //')"; fi
section "$(trn 'Сведения о системе' 'System Details')"
field "$(trn 'Имя машины:' 'Hostname:')" "$GREEN" "$(hostname)"
if flag SHOW_OS; then . /etc/os-release 2>/dev/null || true; field "$(trn 'ОС:' 'OS:')" "$GREEN" "${PRETTY_NAME:-Linux}"; fi
for fam in 4 6; do
 flag "SHOW_IP$fam" || continue
 dest=1.1.1.1; [[ $fam == 6 ]] && dest=2606:4700:4700::1111
 addr=$(ip -"$fam" route get "$dest" 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n1)
 field "External IP (v$fam):" "$PINK" "${addr:-N/A}"
done
if flag SHOW_KERNEL; then field "$(trn 'Ядро:' 'Kernel:')" "$GREEN" "$(uname -r)"; fi
if flag SHOW_HOSTING; then field "$(trn 'Хостер:' 'Hosting:')" "$GREEN" "$(provider || true)"; fi
if flag SHOW_CPU; then
 section 'CPU'
 cpu=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)
 [[ -n $cpu ]] || cpu=$(awk -F: '/model name/ {gsub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo)
 field "$(trn 'Модель:' 'Model:')" "$ORANGE" "${cpu:-Unknown} ($(nproc 2>/dev/null || echo '?') vCPU)"
 # Actual short CPU utilization sample from /proc/stat (not load average).
 read -r _ u n sy idle io irq soft steal _ < /proc/stat
 t1=$((u+n+sy+idle+io+irq+soft+steal)); idle1=$((idle+io))
 sleep 0.15
 read -r _ u n sy idle io irq soft steal _ < /proc/stat
 t2=$((u+n+sy+idle+io+irq+soft+steal)); idle2=$((idle+io))
 delta=$((t2-t1)); cpu_pct=0
 if ((delta>0)); then cpu_pct=$((100*(delta-idle2+idle1)/delta)); fi
 label "$(trn 'Нагрузка:' 'Usage:')"
 bar "$cpu_pct" 100; printf '\n'
 if flag SHOW_LOAD; then field 'Load average:' "$GREEN" "$(cut -d' ' -f1-3 /proc/loadavg)"; fi
fi
if flag SHOW_RAM || flag SHOW_DISK; then section "$(trn 'ОЗУ и диск' 'RAM & Disk')"; fi
if flag SHOW_RAM; then
 read -r mem_total mem_avail < <(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t,a}' /proc/meminfo)
 mem_used=$((mem_total-mem_avail))
 label 'RAM:'; bar "$mem_used" "$mem_total"
 printf ' %b(%s / %s)%b\n' "$GREEN" "$(human_bytes $((mem_used*1024)))" "$(human_bytes $((mem_total*1024)))" "$RESET"
fi
if flag SHOW_DISK; then
 read -r disk_total disk_used < <(df -B1 -P / | awk 'NR==2{print $2,$3}')
 label "$(trn 'Диск:' 'Disk:')"; bar "$disk_used" "$disk_total"
 printf ' %b(%s / %s)%b\n' "$GREEN" "$(human_bytes "$disk_used")" "$(human_bytes "$disk_total")" "$RESET"
 dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
 parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)
 [[ -n $parent ]] || parent=$(lsblk -no NAME "$dev" 2>/dev/null | head -n1 || true)
 if [[ -n $parent && -b /dev/$parent ]]; then
  model=$(lsblk -dn -o MODEL "/dev/$parent" 2>/dev/null | xargs || true)
  [[ -z $model ]] || field "$(trn 'Накопитель:' 'Storage:')" "$GREEN" "$model"
 fi
fi
if [[ ${SHOW_NET:-1} == 1 ]]; then
 section "$(trn 'Сеть' 'Network')"
 iface=$(ip -4 route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
 if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
  field "$(trn 'Интерфейс:' 'Interface:')" "$GREEN" "$iface"
  field "$(trn 'Получено:' 'Received:')" "$GREEN" "$(human_bytes "$(cat /sys/class/net/"$iface"/statistics/rx_bytes)")"
  field "$(trn 'Отправлено:' 'Transmitted:')" "$GREEN" "$(human_bytes "$(cat /sys/class/net/"$iface"/statistics/tx_bytes)")"
 fi
fi
if flag SHOW_UFW; then
 section "$(trn 'Брандмауэр' 'Firewall')"
 if ! command -v ufw >/dev/null 2>&1; then st=$(trn 'не установлен' 'not installed')
 elif ufw status 2>/dev/null | grep -q '^Status: active'; then st='active'
 else st='inactive'; fi
 field "$(trn 'Статус UFW:' 'UFW Status:')" "$GREEN" "$st"
 if [[ ${SHOW_UFW_RULES:-1} == 1 && $st == active ]]; then
  rules=$(ufw status 2>/dev/null | sed -n '/^--/,$p' | tail -n +2 | head -n 8)
  if [[ -n $rules ]]; then
   printf '%b%s%b\n' "$BLUE" "$(trn 'Правила:' 'Rules:')" "$RESET"
   while IFS= read -r rule; do printf '  %s\n' "$rule"; done <<< "$rules"
  fi
 fi
fi
if flag SHOW_DOCKER && command -v docker >/dev/null 2>&1; then
 section 'Docker'
 total=$(timeout 2 docker ps -aq 2>/dev/null | wc -l)
 running=$(timeout 2 docker ps -q 2>/dev/null | wc -l)
 field "$(trn 'Контейнеры:' 'Containers:')" "$GREEN" "$running / $total"
 names=$(timeout 2 docker ps --format '{{.Names}}' 2>/dev/null | head -n 10)
 if [[ -n $names ]]; then
  printf '%b%s%b\n' "$BLUE" "$(trn 'Запущенные контейнеры:' 'Running Containers:')" "$RESET"
  printf '  %s\n' "$names"
 fi
fi
if flag SHOW_UPDATES; then
 section "$(trn 'Доступные обновления' 'Updates Available')"
 count=$(apt list --upgradable 2>/dev/null | awk 'NR>1 && /\[upgradable from:/ {n++} END {print n+0}')
 field "$(trn 'Всего обновлений:' 'Total updates:')" "$ORANGE" "$count $(trn 'пакетов' 'packages')"
 if ((count>0)); then printf '%b%s%b\n' "$BLUE" "$(trn 'Для установки: apt upgrade' 'Run apt upgrade to install updates')" "$RESET"; fi
fi
printf '\n'
RENDER
cat > "$BASE/settings.sh" <<'SETTINGS'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Root required'; exit 1; }
source /opt/midas-motd/lib.sh
TTY=/dev/tty
[[ -r $TTY ]] || { echo 'Interactive terminal required'; exit 1; }
ask() { read -r -p "$1" REPLY < "$TTY"; }
write_setting() {
 local key=$1 value=$2 temp
 [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
 temp=$(mktemp)
 if [[ -f $CFG ]]; then grep -v -E "^${key}=" "$CFG" > "$temp" || true; fi
 printf '%s=%q\n' "$key" "$value" >> "$temp"
 chmod 600 "$temp"; mv "$temp" "$CFG"
 printf -v "$key" '%s' "$value"
}
rename_host() {
 local new old backup cloud_file=/etc/cloud/cloud.cfg.d/99-zz-midas-hostname.cfg
 old=$(hostname)
 printf '%s: %s\n' "$(trn 'Текущее имя' 'Current hostname')" "$old"
 ask "$(trn 'Новое имя (пусто = отмена)' 'New hostname (empty = cancel)'): "
 new=${REPLY,,}; [[ -n $new ]] || return 0
 [[ $new =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || { echo 'Invalid hostname'; return 1; }
 [[ $new != "$old" ]] || return 0
 printf '%s\n' "$(trn 'Внимание: проверьте зависимости сервисов от старого hostname.' 'Warning: check services that depend on the old hostname.')"
 ask "$(trn 'Введите YES для подтверждения' 'Type YES to confirm'): "
 [[ $REPLY == YES ]] || return 0
 backup=$(mktemp -d /root/midas-hostname-backup.XXXXXXXX)
 cp -a /etc/hostname "$backup/hostname" 2>/dev/null || true
 cp -a /etc/hosts "$backup/hosts"
 if [[ -f /etc/cloud/cloud.cfg ]]; then
   mkdir -p /etc/cloud/cloud.cfg.d
   if [[ -e $cloud_file ]]; then cp -a "$cloud_file" "$backup/cloud"; else touch "$backup/cloud-absent"; fi
 fi
 if ! hostnamectl set-hostname "$new"; then echo 'hostnamectl failed'; return 1; fi
 if ! NEW_NAME="$new" OLD_NAME="$old" python3 - <<'PY'
import os
from pathlib import Path
p=Path('/etc/hosts')
old=os.environ['OLD_NAME']; new=os.environ['NEW_NAME']
lines=[]; found=False
for line in p.read_text().splitlines(keepends=True):
    parts=line.partition('#')
    fields=parts[0].split()
    if fields and fields[0]=='127.0.1.1':
        aliases=[new]+[x for x in fields[1:] if x not in (old,new)]
        line='\t'.join(['127.0.1.1']+aliases)+(' #'+parts[2].rstrip('\n') if parts[1] else '')+'\n'
        found=True
    lines.append(line)
if not found: lines.append('127.0.1.1\t'+new+'\n')
p.write_text(''.join(lines))
PY
 then
   cp -a "$backup/hosts" /etc/hosts; hostnamectl set-hostname "$old" || true; return 1
 fi
 if [[ -f /etc/cloud/cloud.cfg ]]; then
   printf '# MIDAS MOTD: preserve manually configured hostname\npreserve_hostname: true\n' > "$cloud_file"
 fi
 if [[ $(hostname) != "$new" ]]; then
   cp -a "$backup/hosts" /etc/hosts
   [[ ! -f $backup/hostname ]] || cp -a "$backup/hostname" /etc/hostname
   if [[ -f $backup/cloud ]]; then cp -a "$backup/cloud" "$cloud_file"; elif [[ -f $backup/cloud-absent ]]; then rm -f "$cloud_file"; fi
   hostnamectl set-hostname "$old" || true
   echo 'Verification failed; rolled back'; return 1
 fi
 echo "Hostname: $old -> $new"
 echo "Backup: $backup"
}
ui() {
 local title=$1; shift
 if command -v whiptail >/dev/null 2>&1; then
  whiptail --title "$title" "$@" 3>&1 1>&2 2>&3
 elif command -v dialog >/dev/null 2>&1; then
  dialog --stdout --title "$title" "$@"
 else
  return 127
 fi
}
notice() {
 if command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1; then
  ui "MIDAS MOTD" --msgbox "$1" 10 65 || true
 else printf '%s\n' "$1"; fi
}
choose() {
 local title=$1; shift
 if command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1; then
  ui "$title" --menu "$(trn 'Выберите действие:' 'Choose an action:')" 22 76 13 "$@"
 else
  local i=1 tag label
  printf '\n%s\n' "$title" >&2
  while (($#)); do tag=$1; label=$2; shift 2; printf '%s) %s\n' "$tag" "$label" >&2; done
  read -r -p '> ' tag < /dev/tty
  printf '%s' "$tag"
 fi
}
prompt_value() {
 local title=$1 default=${2:-}
 if command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1; then
  ui "MIDAS MOTD" --inputbox "$title" 10 70 "$default"
 else
  read -r -p "$title: " REPLY < /dev/tty
  printf '%s' "${REPLY:-$default}"
 fi
}
confirm_action() {
 local message=$1
 if command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1; then
  ui "MIDAS MOTD" --yesno "$message" 10 70
 else
  read -r -p "$message [y/N]: " REPLY < /dev/tty
  [[ $REPLY == y || $REPLY == Y ]]
 fi
}
toggle_menu() {
 local key label selected
 while true; do
  source /opt/midas-motd/lib.sh
  selected=$(choose "$(trn 'Настроить отображение MOTD' 'Configure MOTD display')" \
   1 "IPv4: $SHOW_IP4" 2 "IPv6: $SHOW_IP6" 3 "$(trn 'Хостер' 'Hosting'): $SHOW_HOSTING" \
   4 "$(trn 'Ядро' 'Kernel'): $SHOW_KERNEL" 5 "$(trn 'Обновления' 'Updates'): $SHOW_UPDATES" \
   6 "UFW: $SHOW_UFW" 7 "CPU: $SHOW_CPU" 8 "RAM: $SHOW_RAM" 9 "$(trn 'Диск' 'Disk'): $SHOW_DISK" \
   10 "Docker: $SHOW_DOCKER" 11 "$(trn 'Сеть' 'Network'): $SHOW_NET" \
   12 "$(trn 'Правила UFW' 'UFW rules'): $SHOW_UFW_RULES" 0 "$(trn 'Назад' 'Back')" ) || return 0
  [[ $selected == 0 ]] && return 0
  local keys=(SHOW_IP4 SHOW_IP6 SHOW_HOSTING SHOW_KERNEL SHOW_UPDATES SHOW_UFW SHOW_CPU SHOW_RAM SHOW_DISK SHOW_DOCKER SHOW_NET SHOW_UFW_RULES)
  [[ $selected =~ ^[0-9]+$ ]] && ((selected>=1 && selected<=12)) || continue
  key=${keys[selected-1]}
  if [[ ${!key} == 1 ]]; then write_setting "$key" 0; else write_setting "$key" 1; fi
 done
}
menu() {
 local selected val
 while true; do
  source /opt/midas-motd/lib.sh
  selected=$(choose "MIDAS MOTD" \
   1 "$(trn 'Настроить отображение MOTD' 'Configure MOTD display')" \
   2 "$(trn 'Настроить Services Status' 'Configure Services Status')" \
   3 "$(trn 'Удалить MIDAS MOTD' 'Uninstall MIDAS MOTD')" \
   4 "$(trn 'Показать статус установки' 'Installation status')" \
   5 "$(trn 'Цветовая тема' 'Color theme'): $THEME" \
   6 "$(trn 'Язык' 'Language'): $LANGUAGE" \
   7 "$(trn 'Изменить имя машины (hostname)' 'Change machine hostname')" \
   8 "$(trn 'Название сервера' 'Server display name'): ${SERVER_LABEL:-auto}" \
   9 "$(trn 'Название хостера' 'Hosting name'): ${HOSTING_NAME:-auto}" \
   10 "$(trn 'Обновить информацию о хостере' 'Refresh hosting information')" \
   11 "$(trn 'Предпросмотр MOTD' 'Preview MOTD')" \
   0 "$(trn 'Выход' 'Exit')" ) || break
  case $selected in
   0) break;;
   1) toggle_menu;;
   2) notice "$(trn 'Статус Docker доступен в настройках отображения. Отдельные проверки служб появятся в следующем обновлении.' 'Docker status is available under display settings. Custom service checks are not yet implemented.')";;
   3) if confirm_action "$(trn 'Удалить MIDAS MOTD? Имя машины останется прежним.' 'Uninstall MIDAS MOTD? Hostname will remain unchanged.')"; then /opt/midas-motd/uninstall.sh; exit 0; fi;;
   4) notice "$(trn 'MIDAS MOTD установлен. Конфигурация:' 'MIDAS MOTD installed. Configuration:') $CFG";;
   5) val=$(choose "$(trn 'Цветовая тема' 'Color theme')" cyan Cyan green Green purple Purple blue Blue none None) || continue
      case $val in cyan|green|purple|blue|none) write_setting THEME "$val";; esac;;
   6) if [[ $LANGUAGE == ru ]]; then write_setting LANGUAGE en; else write_setting LANGUAGE ru; fi;;
   7) rename_host || true;;
   8) val=$(prompt_value "$(trn 'Название сервера (пусто = hostname)' 'Server name (empty = hostname)')" "$SERVER_LABEL") || continue; write_setting SERVER_LABEL "$val";;
   9) val=$(prompt_value "$(trn 'Название хостера (пусто = автоматически)' 'Hosting name (empty = auto)')" "$HOSTING_NAME") || continue; write_setting HOSTING_NAME "$val";;
   10) /opt/midas-motd/refresh-provider.sh || notice "$(trn 'Не удалось получить данные хостера' 'Hosting lookup failed')";;
   11) clear; /opt/midas-motd/render.sh; read -r -p "$(trn 'Нажмите Enter...' 'Press Enter...')" REPLY < /dev/tty;;
  esac
 done
}

menu
SETTINGS
cat > "$BASE/refresh-provider.sh" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail
command -v curl >/dev/null || { echo 'curl not installed'; exit 1; }
mkdir -p /var/cache
value=$(curl -4fsSL --connect-timeout 3 --max-time 8 https://ipinfo.io/org | head -c 120)
[[ -n $value ]] || exit 1
printf '%s\n' "$value" > /var/cache/midas-motd-provider
printf 'Hosting ASN: %s\n' "$value"
PROVIDER
cat > "$BASE/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID == 0 ]] || exit 1
BASE=/opt/midas-motd
BACK=$BASE/backup
rm -f /etc/update-motd.d/00-midas /usr/local/bin/motd /usr/local/bin/motd-set
for f in /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/00-dist-motd /usr/local/bin/motd /usr/local/bin/motd-set; do
 [[ ! -e $BACK$f ]] || { mkdir -p "$(dirname "$f")"; cp -a "$BACK$f" "$f"; }
done
rm -f /etc/midas-motd.conf
# Intentionally preserve the system hostname and cloud-init hostname policy.
# A renamed machine must not be silently renamed back on uninstall.
echo 'MIDAS MOTD removed. Hostname and cloud-init hostname policy preserved.'
UNINSTALL
for f in "$BASE"/*.sh; do chmod 755 "$f"; done
if [[ ! -f $CFG ]]; then
 cat > "$CFG" <<'CONFIG'
LANGUAGE=ru
THEME=cyan
SERVER_LABEL=''
HOSTING_NAME=''
SHOW_IP4=1
SHOW_IP6=1
SHOW_HOSTING=1
SHOW_KERNEL=1
SHOW_UPDATES=1
SHOW_UFW=1
SHOW_CPU=1
SHOW_RAM=1
SHOW_DISK=1
SHOW_DOCKER=1
SHOW_UPTIME=1
SHOW_LOAD=1
SHOW_OS=1
SHOW_NET=1
SHOW_UFW_RULES=1
CONFIG
 chmod 600 "$CFG"
fi
cat > "$MOTD" <<'RUN'
#!/usr/bin/env bash
exec /opt/midas-motd/render.sh
RUN
chmod 755 "$MOTD"
cat > /usr/local/bin/motd <<'RUN'
#!/usr/bin/env bash
exec /opt/midas-motd/render.sh
RUN
cat > /usr/local/bin/motd-set <<'RUN'
#!/usr/bin/env bash
exec /opt/midas-motd/settings.sh
RUN
chmod 755 /usr/local/bin/motd /usr/local/bin/motd-set
# Avoid duplicate standard dynamic MOTD fragments, but keep backups.
for f in /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news /etc/update-motd.d/00-dist-motd; do
 [[ ! -f $f ]] || chmod a-x "$f"
done
# Do not edit PAM, SSH or restart sshd: existing pam_motd will execute update-motd.d.
touch "$BASE/installed"
if [[ ! -f "$BASE/setup-complete" ]]; then
 touch "$BASE/setup-complete"
 printf '\nУстановка завершена. Для настройки запустите: motd-set\n'
fi
printf '\nCommands: motd, motd-set\n'
