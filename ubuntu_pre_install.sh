#!/bin/bash

set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.1"
SCRIPT_DATE="2025-02-20 18:21:09"
SCRIPT_AUTHOR="gopnikgame"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Функция отката изменений с улучшенной обработкой ошибок
rollback() {
    log "ERROR" "Произошла ошибка. Выполняется откат изменений..."
    
    # Восстановление DNS конфигурации
    if [ -f "$BACKUP_DIR/resolved.conf" ]; then
        cp "$BACKUP_DIR/resolved.conf" /etc/systemd/resolved.conf || true
        systemctl unmask systemd-resolved || true
        systemctl restart systemd-resolved || true
    fi
    
    # Восстановление resolv.conf
    if [ -f "$BACKUP_DIR/resolv.conf" ]; then
        cp "$BACKUP_DIR/resolv.conf" /etc/resolv.conf || true
    fi
    
    # Восстановление локали
    if [ -f "$BACKUP_DIR/locale" ]; then
        cp "$BACKUP_DIR/locale" /etc/default/locale || true
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

# Создание резервных копий
log "INFO" "Создание резервных копий конфигурационных файлов..."
mkdir -p "$BACKUP_DIR"
cp -r /etc/systemd/resolved.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -r /etc/resolv.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -r /etc/default/locale "$BACKUP_DIR/" 2>/dev/null || true

# Обновление системы
log "INFO" "Обновление списка пакетов и системы..."
apt update
apt upgrade -y
apt dist-upgrade -y

# Установка базовых пакетов
log "INFO" "Установка базовых пакетов..."
apt install -y \
    curl wget git htop neofetch mc \
    net-tools nmap tcpdump iotop \
    unzip tar vim tmux screen \
    rsync ncdu dnsutils resolvconf \
    chrony fail2ban

# Настройка локали
log "INFO" "Настройка русской локали..."
apt install -y language-pack-ru
locale-gen ru_RU.UTF-8
update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8
dpkg-reconfigure -f noninteractive locales

# Настройка временной зоны
log "INFO" "Настройка временной зоны..."
timedatectl set-timezone Europe/Moscow

# Настройка синхронизации времени (используем chrony вместо ntp)
log "INFO" "Настройка Chrony..."
systemctl stop ntp || true
systemctl disable ntp || true
apt remove -y ntp || true
systemctl enable chronyd
systemctl start chronyd

# Настройка DNS
log "INFO" "Настройка DNS..."
# Размаскировка systemd-resolved
systemctl unmask systemd-resolved || true
systemctl stop systemd-resolved || true

# Настройка DNS через resolv.conf
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

# Защита resolv.conf от изменений
chattr +i /etc/resolv.conf

# Настройка файрволла
log "INFO" "Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
yes | ufw enable

# Настройка SSH
log "INFO" "Настройка безопасности SSH..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/"
cat >> /etc/ssh/sshd_config << EOF

# Дополнительные настройки безопасности
PermitRootLogin prohibit-password
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
Protocol 2
AllowAgentForwarding no
AllowTcpForwarding no
LoginGraceTime 30
EOF

systemctl restart sshd

# Настройка fail2ban
log "INFO" "Настройка fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl start fail2ban

# Оптимизация системных параметров
log "INFO" "Настройка системных параметров..."
cat >> /etc/sysctl.conf << EOF

# Оптимизация системы
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_max_tw_buckets = 720000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
EOF

sysctl -p

# Финальная информация
log "INFO" "=== Установка завершена ==="
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Log file: $LOG_FILE"

# Запрос на перезагрузку
read -p "Перезагрузить систему сейчас? (y/n): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    log "INFO" "Выполняется перезагрузка..."
    shutdown -r now
else
    log "WARNING" "Перезагрузка отложена. Рекомендуется перезагрузить систему позже."
fi