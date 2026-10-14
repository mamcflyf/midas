
#!/usr/bin/env bash
set -e

[[ $EUID -eq 0 ]] || { echo "Запусти от root: sudo bash $0"; exit 1; }

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${GREEN}▶ $1${NC}"; }

step "Установка зависимостей"
apt update
apt install -y wget gnupg lsb-release

step "Добавление репозитория XanMod"
install -d /etc/apt/keyrings
wget -qO- https://dl.xanmod.org/archive.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/xanmod-release.list

step "Установка ядра XanMod x64v3"
apt update
apt install -y linux-xanmod-x64v3

echo -e "\n${GREEN}✓ Готово! Перезагрузи сервер: reboot${NC}"
