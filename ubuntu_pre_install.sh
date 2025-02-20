#!/bin/bash
set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.4"
SCRIPT_DATE="2025-02-20 18:21:09"
SCRIPT_AUTHOR="gopnikgame"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Константы
BACKUP_DIR="/root/config_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/system_setup.log"
MIN_FREE_SPACE_KB=5242880  # 5GB в килобайтах

# Функция логирования с цветным выводом
log() {
    local level="$1"
    shift
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    case "$level" in
        "INFO") local color=$GREEN ;;
        "WARNING") local color=$YELLOW ;;
        "ERROR") local color=$RED ;;
        *) local color=$NC ;;
    esac
    echo -e "${timestamp} [${color}${level}${NC}] $*"
    echo "${timestamp} [${level}] $*" >> "$LOG_FILE"
}

# Функция отката изменений
rollback() {
    log "ERROR" "Произошла ошибка. Выполняется откат изменений..."
    if [ -f "$BACKUP_DIR/resolved.conf" ]; then
        cp "$BACKUP_DIR/resolved.conf" /etc/systemd/resolved.conf || true
        systemctl restart systemd-resolved || true
    fi
    exit 1
}

# Установка обработчика ошибок
trap rollback ERR

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Проверка root прав
if [ "$EUID" -ne 0 ]; then 
    log "ERROR" "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Проверка свободного места на диске
check_free_space() {
    local free_space_kb=$(df -k --output=avail "$PWD" | tail -n1)
    if [ "$free_space_kb" -lt "$MIN_FREE_SPACE_KB" ]; then
        log "ERROR" "Недостаточно свободного места на диске. Требуется минимум $((MIN_FREE_SPACE_KB / 1024)) MB."
        exit 1
    fi
}

log "INFO" "Проверка свободного места на диске..."
check_free_space

# Создание резервных копий
backup_file() {
    local src="$1"
    if [ -f "$src" ]; then
        cp "$src" "$BACKUP_DIR/" || { log "ERROR" "Не удалось создать резервную копию: $src"; exit 1; }
    else
        log "WARNING" "Файл не найден для резервного копирования: $src"
    fi
}

log "INFO" "Создание резервных копий конфигурационных файлов..."
mkdir -p "$BACKUP_DIR"
backup_file "/etc/systemd/resolved.conf"

# Обновление системы
log "INFO" "Обновление списка пакетов и системы..."
apt update
apt upgrade -y
apt dist-upgrade -y

# Настройка DNS через systemd-resolved
log "INFO" "Настройка DNS через systemd-resolved..."
cat > /etc/systemd/resolved.conf << EOF
[Resolve]
# Основной DNS: Google DoH
DNS=8.8.8.8#dns.google
FallbackDNS=1.1.1.1#cloudflare-dns.com 94.140.14.14#dns.adguard.com
Domains=~.
DNSOverTLS=yes
DNSSEC=yes

# Кеширование DNS
Cache=yes
CacheFromLocalhost=yes
DNSStubListener=yes
EOF

# Убедитесь, что resolv.conf является символической ссылкой
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

systemctl unmask systemd-resolved
systemctl enable systemd-resolved
systemctl restart systemd-resolved

# Настройка файрволла
log "INFO" "Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
yes | ufw enable

# Настройка SSH
update_ssh_config() {
    local key="$1"
    local value="$2"
    if ! grep -q "^$key" /etc/ssh/sshd_config; then
        echo "$key $value" >> /etc/ssh/sshd_config
    else
        sed -i "s/^$key.*/$key $value/" /etc/ssh/sshd_config
    fi
}

log "INFO" "Настройка безопасности SSH..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/"
update_ssh_config "PermitRootLogin" "prohibit-password"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "X11Forwarding" "no"
update_ssh_config "MaxAuthTries" "3"
update_ssh_config "Protocol" "2"
update_ssh_config "AllowAgentForwarding" "no"
update_ssh_config "AllowTcpForwarding" "no"
update_ssh_config "LoginGraceTime" "30"

systemctl restart sshd

# Настройка fail2ban
log "INFO" "Настройка fail2ban..."
if [ -f "/etc/fail2ban/jail.conf" ]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
else
    log "WARNING" "Файл jail.conf не найден. Настройка fail2ban пропущена."
fi

systemctl enable fail2ban
systemctl start fail2ban

# Финальная информация
log "INFO" "=== Установка завершена ==="
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Log file: $LOG_FILE"

# Запрос на перезагрузку
if tty -s; then
    read -p "Перезагрузить систему сейчас? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log "INFO" "Выполняется перезагрузка..."
        shutdown -r now
    else
        log "WARNING" "Перезагрузка отложена. Рекомендуется перезагрузить систему позже."
    fi
else
    log "INFO" "Скрипт запущен в неинтерактивном режиме. Перезагрузка не выполняется."
fi