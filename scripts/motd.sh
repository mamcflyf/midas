#!/usr/bin/env bash
# MIDAS MOTD - self-contained Debian/Ubuntu installer (MIT)
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run as root / Запустите от root' >&2; exit 1; }
[[ -f /etc/debian_version ]] || { echo 'Debian/Ubuntu only' >&2; exit 1; }
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
SHOW_UPTIME=1; SHOW_LOAD=1; SHOW_OS=1; SHOW_LASTLOGIN=0
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
export LC_ALL=C
printf '\n'; color; printf '  ◆ MIDAS MOTD'; reset; printf '  |  %s\n' "${SERVER_LABEL:-$(hostname)}"
heading "$(trn 'СИСТЕМА' 'SYSTEM')"
if flag SHOW_OS; then . /etc/os-release 2>/dev/null || true; line "$(trn 'ОС' 'OS')" "${PRETTY_NAME:-Linux}"; fi
if flag SHOW_KERNEL; then line "$(trn 'Ядро' 'Kernel')" "$(uname -r)"; fi
if flag SHOW_UPTIME; then line "$(trn 'Время работы' 'Uptime')" "$(uptime -p 2>/dev/null || echo '?')"; fi
if flag SHOW_LOAD; then line "$(trn 'Нагрузка' 'Load')" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"; fi
if flag SHOW_CPU; then
 cpu=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)
 [[ -n $cpu ]] || cpu=$(awk -F: '/model name/ {gsub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo)
 line 'CPU' "${cpu:-Unknown} ($(nproc 2>/dev/null || echo '?') vCPU)"
fi
if flag SHOW_RAM; then line 'RAM' "$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2 " (available " $7 ")"}')"; fi
if flag SHOW_DISK; then
 dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
 parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)
 [[ -n $parent ]] || parent=$(lsblk -no NAME "$dev" 2>/dev/null | head -n1 || true)
 model='Virtual / Unknown'; transport=''
 if [[ -n $parent && -b /dev/$parent ]]; then
   value=$(lsblk -dn -o MODEL "/dev/$parent" 2>/dev/null | xargs || true)
   [[ -z $value ]] || model=$value
   transport=$(lsblk -dn -o TRAN "/dev/$parent" 2>/dev/null | xargs || true)
 fi
 line "$(trn 'Накопитель' 'Storage')" "$model${transport:+ ($transport)}"
 line "$(trn 'Диск /' 'Disk /')" "$(df -hP / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
fi
heading "$(trn 'СЕТЬ' 'NETWORK')"
for fam in 4 6; do
 flag "SHOW_IP$fam" || continue
 if [[ $fam == 4 ]]; then dest=1.1.1.1; else dest=2606:4700:4700::1111; fi
 addr=$(ip -"$fam" route get "$dest" 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n1)
 line "IPv$fam" "${addr:-$(trn 'Недоступен' 'Unavailable')}"
done
if flag SHOW_HOSTING; then line "$(trn 'Хостер' 'Hosting')" "$(provider)"; fi
heading "$(trn 'БЕЗОПАСНОСТЬ' 'SECURITY')"
if flag SHOW_UFW; then
 if ! command -v ufw >/dev/null 2>&1; then st=$(trn 'Не установлен' 'Not installed')
 elif ufw status 2>/dev/null | grep -q '^Status: active'; then st=$(trn 'ВКЛЮЧЁН' 'ACTIVE')
 else st=$(trn 'ВЫКЛЮЧЕН' 'INACTIVE'); fi
 line UFW "$st"
fi
if flag SHOW_UPDATES; then
 count=$(apt list --upgradable 2>/dev/null | awk 'NR>1 && /\[upgradable from:/ {n++} END {print n+0}')
 line "$(trn 'Обновления' 'Updates')" "$count $(trn 'пакетов (кэш APT)' 'packages (APT cache)')"
fi
if flag SHOW_DOCKER && command -v docker >/dev/null 2>&1; then
 running=$(timeout 2 docker ps -q 2>/dev/null | wc -l)
 line Docker "$running $(trn 'запущено' 'running')"
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
menu() {
 while true; do
  source /opt/midas-motd/lib.sh
  printf '\n=== MIDAS MOTD ===\n'
  printf ' 1) %s: %s\n' "$(trn 'Язык' 'Language')" "$LANGUAGE"
  printf ' 2) %s: %s\n' "$(trn 'Тема' 'Theme')" "$THEME"
  printf ' 3) %s\n' "$(trn 'Изменить hostname Linux' 'Change Linux hostname')"
  printf ' 4) %s: %s\n' "$(trn 'Название сервера' 'Server label')" "${SERVER_LABEL:-auto}"
  printf ' 5) %s: %s\n' "$(trn 'Название хостера' 'Hosting name')" "${HOSTING_NAME:-auto}"
  local i=6 k
  for k in SHOW_IP4 SHOW_IP6 SHOW_HOSTING SHOW_KERNEL SHOW_UPDATES SHOW_UFW SHOW_CPU SHOW_RAM SHOW_DISK SHOW_DOCKER SHOW_UPTIME SHOW_LOAD SHOW_OS; do
    printf '%2d) %-17s [%s]\n' "$i" "${k#SHOW_}" "${!k}"
    ((i+=1))
  done
  printf '19) %s\n20) %s\n21) %s\n 0) %s\n' "$(trn 'Показать MOTD' 'Preview MOTD')" "$(trn 'Обновить данные хостера' 'Refresh hosting info')" "$(trn 'Удалить MIDAS MOTD' 'Uninstall MIDAS MOTD')" "$(trn 'Выход' 'Exit')"
  ask '> '
  case $REPLY in
   0) break;;
   1) if [[ $LANGUAGE == ru ]]; then write_setting LANGUAGE en; else write_setting LANGUAGE ru; fi;;
   2) ask 'cyan / green / purple / blue / none: '; case $REPLY in cyan|green|purple|blue|none) write_setting THEME "$REPLY";; esac;;
   3) rename_host || true;;
   4) ask "$(trn 'Название сервера (пусто = hostname)' 'Server label (empty = hostname)'): "; write_setting SERVER_LABEL "$REPLY";;
   5) ask "$(trn 'Хостер (пусто = авто)' 'Hosting (empty = auto)'): "; write_setting HOSTING_NAME "$REPLY";;
   19) /opt/midas-motd/render.sh;;
   20) /opt/midas-motd/refresh-provider.sh;;
   21) ask 'Type REMOVE to uninstall / Введите REMOVE для удаления: '; if [[ $REPLY == REMOVE ]]; then /opt/midas-motd/uninstall.sh; exit 0; fi;;
   *) if [[ $REPLY =~ ^([0-9]+)$ ]] && (( REPLY >= 6 && REPLY <= 18 )); then
      local keys=(SHOW_IP4 SHOW_IP6 SHOW_HOSTING SHOW_KERNEL SHOW_UPDATES SHOW_UFW SHOW_CPU SHOW_RAM SHOW_DISK SHOW_DOCKER SHOW_UPTIME SHOW_LOAD SHOW_OS)
      k=${keys[REPLY-6]}; if [[ ${!k} == 1 ]]; then write_setting "$k" 0; else write_setting "$k" 1; fi
      fi;;
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
if [[ -r /dev/tty ]]; then
 printf '\nMIDAS MOTD installed. Initial setup / Первоначальная настройка:\n'
 /opt/midas-motd/settings.sh </dev/tty
fi
printf '\nCommands: motd, motd-set\n'
