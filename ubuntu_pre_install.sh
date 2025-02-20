#!/bin/bash
set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.0"
SCRIPT_DATE="2025-02-20"
SCRIPT_AUTHOR="gopnikgame"

# Константы
BACKUP_DIR="/root/config_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/system_setup.log"
MIN_FREE_SPACE_KB=5242880  # 5GB в килобайтах

# Функция логирования
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Функция отката изменений
rollback() {
    log "ERROR" "Произошла ошибка. Выполняется откат изменений..."
    [ -f "$BACKUP_DIR/resolved.conf" ] && cp "$BACKUP_DIR/resolved.conf" /etc/systemd/resolved.conf
    [ -f "$BACKUP_DIR/resolv.conf" ] && cp "$BACKUP_DIR/resolv.conf" /etc/resolv.conf
    systemctl restart systemd-resolved
    exit 1
}

# Установка обработчика ошибок
trap rollback ERR

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# Начало установки
log "INFO" "=== Начало установки ==="
log "INFO" "Версия скрипта: $SCRIPT_VERSION"
log "INFO" "Дата запуска: $(date +'%Y-%m-%d %H:%M:%S')"
log "INFO" "Пользователь: $(whoami)"

# Проверка root прав
if [ "$EUID" -ne 0 ]; then 
    log "ERROR" "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Проверка версии Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    log "ERROR" "Этот скрипт предназначен только для Ubuntu"
    exit 1
fi

# Проверка свободного места
FREE_SPACE=$(df -k / | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_FREE_SPACE_KB" ]; then
    log "ERROR" "Недостаточно свободного места на диске (минимум 5GB)"
    exit 1
fi

# Проверка наличия необходимых команд
for cmd in apt ufw systemctl resolvectl; do
    if ! command -v "$cmd" &> /dev/null; then
        log "ERROR" "Команда '$cmd' не найдена"
        exit 1
    fi
done

# Создание резервных копий
log "INFO" "Создание резервных копий конфигурационных файлов..."
mkdir -p "$BACKUP_DIR"
cp -r /etc/systemd/resolved.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -r /etc/resolv.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -r /etc/default/locale "$BACKUP_DIR/" 2>/dev/null || true

# Обновление системы
log "INFO" "Обновление списка пакетов и системы..."
if ! apt update; then
    log "ERROR" "Ошибка при обновлении списка пакетов"
    exit 1
fi
apt upgrade -y
apt dist-upgrade -y
apt autoremove -y
apt autoclean

# Установка базовых пакетов
log "INFO" "Установка базовых пакетов..."
apt install -y \
    curl \
    wget \
    git \
    htop \
    neofetch \
    mc \
    net-tools \
    nmap \
    tcpdump \
    iotop \
    unzip \
    tar \
    vim \
    tmux \
    screen \
    rsync \
    ncdu \
    dnsutils \
    resolvconf \
    ntp \
    fail2ban

# Настройка локали
log "INFO" "Настройка русской локали..."
apt install -y language-pack-ru
locale-gen ru_RU.UTF-8
update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8
dpkg-reconfigure -f noninteractive locales

# Настройка временной зоны
log "INFO" "Настройка временной зоны..."
timedatectl set-timezone Europe/Moscow

# Настройка NTP
log "INFO" "Настройка NTP..."
systemctl enable ntp
systemctl start ntp

# Настройка DNS через systemd-resolved
log "INFO" "Настройка DNS..."
cat > /etc/systemd/resolved.conf << EOF
[Resolve]
# Основной DNS (Google DoH)
DNS=https://dns.google/dns-query
# Резервные DNS (Cloudflare DoH и обычные серверы)
FallbackDNS=https://cloudflare-dns.com/dns-query 8.8.8.8 8.8.4.4 1.1.1.1
# Включаем DNS-over-TLS и DNSSEC
DNSOverTLS=yes
DNSSEC=yes
# Включаем кеширование DNS
Cache=yes
# Разрешаем разрешение одиночных меток
ResolveUnicastSingleLabel=yes
# Используем локальный файл hosts
ReadEtcHosts=yes
EOF

# Перезапуск DNS
systemctl restart systemd-resolved
systemctl enable systemd-resolved

# Настройка resolv.conf
if [[ -L /etc/resolv.conf ]]; then
    log "INFO" "/etc/resolv.conf уже является символической ссылкой"
else
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# Проверка DNS
log "INFO" "Проверка DNS конфигурации..."
if ! resolvectl status | grep -q "DNS Servers"; then
    log "ERROR" "Ошибка настройки DNS серверов"
    exit 1
fi

# Проверка разрешения имен
if ! host -t A google.com >/dev/null; then
    log "WARNING" "Проблемы с разрешением DNS"
fi

# Настройка файрволла
log "INFO" "Настройка UFW..."
if command -v ufw >/dev/null 2>&1; then
    ufw status verbose > "$BACKUP_DIR/ufw_rules_backup"
fi

ufw default deny incoming
ufw default allow outgoing
ufw limit ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Базовая настройка безопасности SSH
log "INFO" "Настройка безопасности SSH..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/"
cat >> /etc/ssh/sshd_config << EOF

# Дополнительные настройки безопасности
PermitRootLogin no
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
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

# Создание файла с информацией о системе
log "INFO" "Сохранение информации о системе..."
cat > /root/system_setup_info.txt << EOF
=== Информация о настройке системы ===
Дата настройки: $(date)
Версия скрипта: $SCRIPT_VERSION
Hostname: $(hostname)
IP адреса: 
$(ip addr show | grep "inet " | awk '{print $2}')

DNS серверы:
$(resolvectl status | grep "DNS Servers")

Статус служб:
- systemd-resolved: $(systemctl is-active systemd-resolved)
- fail2ban: $(systemctl is-active fail2ban)
- ntp: $(systemctl is-active ntp)
- ufw: $(systemctl is-active ufw)

Установленные пакеты:
$(dpkg --get-selections | grep -v deinstall)

Файрволл (UFW) статус:
$(ufw status verbose)
EOF

# Копирование лога установки
cp "$LOG_FILE" "$BACKUP_DIR/"

log "INFO" "=== Установка завершена ==="
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Log file: $LOG_FILE"
log "INFO" "System info: /root/system_setup_info.txt"

# Запрос на перезагрузку
read -p "Перезагрузить систему сейчас? (y/n): " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    log "INFO" "Выполняется перезагрузка..."
    shutdown -r now
else
    log "WARNING" "Перезагрузка отложена. Не забудьте перезагрузить систему позже."
fi