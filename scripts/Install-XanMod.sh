
#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}➜${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "\n${RED}✗ Ошибка:${NC} $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Запусти от root: sudo bash $0"

export DEBIAN_FRONTEND=noninteractive

step "Обновление списка пакетов"
apt-get update -qq || fail "Не удалось обновить пакеты"

step "Установка зависимостей"
apt-get install -y -qq wget gnupg lsb-release >/dev/null \
  || fail "Не удалось установить зависимости"

step "Подключение репозитория XanMod"
install -d -m 0755 /etc/apt/keyrings

wget -qO- https://dl.xanmod.org/archive.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg \
  || fail "Не удалось добавить ключ XanMod"

chmod 0644 /etc/apt/keyrings/xanmod-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/xanmod-release.list

step "Обновление репозиториев"
apt-get update -qq || fail "Не удалось обновить репозитории XanMod"

step "Установка ядра XanMod x64v3"
apt-get install -y -qq linux-xanmod-x64v3 >/dev/null \
  || fail "Не удалось установить ядро"

echo
ok "Установка завершена"
echo -e "Перезагрузка: ${CYAN}reboot${NC}"
