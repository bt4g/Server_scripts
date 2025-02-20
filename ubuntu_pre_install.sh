#!/bin/bash
set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.1"
SCRIPT_DATE="2025-02-20"
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

# Функция для красивого вывода информации
print_header() {
    local title="$1"
    local width=50
    local padding=$(( (width - ${#title}) / 2 ))
    echo
    echo -e "${BLUE}┌$( printf '─%.0s' $(seq 1 $width) )┐${NC}"
    echo -e "${BLUE}│$( printf ' %.0s' $(seq 1 $padding) )${CYAN}$title$( printf ' %.0s' $(seq 1 $(( width - padding - ${#title} )) ) )${BLUE}│${NC}"
    echo -e "${BLUE}└$( printf '─%.0s' $(seq 1 $width) )┘${NC}"
    echo
}

print_step() {
    echo -e "${YELLOW}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✔${NC} $1"
}

print_error() {
    echo -e "${RED}✘${NC} $1"
}

# Функция логирования
log() {
    local level="$1"
    shift
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO") local color=$GREEN ;;
        "WARNING") local color=$YELLOW ;;
        "ERROR") local color=$RED ;;
        *) local color=$NC ;;
    esac
    echo -e "[${timestamp}] [${color}${level}${NC}] $*" | tee -a "$LOG_FILE"
}

# Функция отката изменений
rollback() {
    print_header "ОТКАТ ИЗМЕНЕНИЙ"
    log "ERROR" "Произошла ошибка. Выполняется откат изменений..."
    
    # Восстановление DNS конфигурации
    if [ -f "$BACKUP_DIR/resolved.conf" ]; then
        cp "$BACKUP_DIR/resolved.conf" /etc/systemd/resolved.conf
        systemctl restart systemd-resolved || true
    fi
    
    # Восстановление resolv.conf
    if [ -f "$BACKUP_DIR/resolv.conf" ]; then
        cp "$BACKUP_DIR/resolv.conf" /etc/resolv.conf
    fi
    
    # Восстановление локали
    if [ -f "$BACKUP_DIR/locale" ]; then
        cp "$BACKUP_DIR/locale" /etc/default/locale
    fi
    
    log "INFO" "Откат изменений завершен"
    exit 1
}

# Установка обработчика ошибок
trap rollback ERR

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# Начало установки
print_header "УСТАНОВКА UBUNTU PRE-INSTALL v${SCRIPT_VERSION}"
log "INFO" "Дата запуска: $(date +'%Y-%m-%d %H:%M:%S')"
log "INFO" "Пользователь: $(whoami)"

# Проверка root прав
if [ "$EUID" -ne 0 ]; then 
    print_error "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Сбор информации о системе
print_header "ИНФОРМАЦИЯ О СИСТЕМЕ"
echo -e "${CYAN}Дата и время (UTC):${NC} $(date -u '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}Текущий пользователь:${NC} $(whoami)"
echo -e "${CYAN}Hostname:${NC} $(hostname)"
echo -e "${CYAN}ОС:${NC} $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo -e "${CYAN}Ядро:${NC} $(uname -r)"
echo -e "${CYAN}CPU:${NC} $(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | sed 's/^[ \t]*//')"
echo -e "${CYAN}RAM:${NC} $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "${CYAN}Диск:${NC} $(df -h / | awk 'NR==2 {print $2}')"

# Проверка версии Ubuntu
print_header "ПРОВЕРКА СИСТЕМЫ"
if ! grep -q "Ubuntu" /etc/os-release; then
    print_error "Этот скрипт предназначен только для Ubuntu"
    exit 1
fi

# Проверка свободного места
FREE_SPACE=$(df -k / | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE" -lt "$MIN_FREE_SPACE_KB" ]; then
    print_error "Недостаточно свободного места на диске (минимум 5GB)"
    exit 1
fi

# Проверка наличия необходимых команд
print_step "Проверка необходимых команд..."
for cmd in apt ufw systemctl resolvectl; do
    if ! command -v "$cmd" &> /dev/null; then
        print_error "Команда '$cmd' не найдена"
        exit 1
    fi
    print_success "Команда $cmd найдена"
done

# Создание резервных копий
print_header "СОЗДАНИЕ РЕЗЕРВНЫХ КОПИЙ"
mkdir -p "$BACKUP_DIR"
for file in "/etc/systemd/resolved.conf" "/etc/resolv.conf" "/etc/default/locale"; do
    if [ -f "$file" ]; then
        cp -r "$file" "$BACKUP_DIR/" 2>/dev/null && print_success "Копия $file создана" || print_error "Ошибка копирования $file"
    fi
done

# Обновление системы
print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
print_step "Обновление списка пакетов..."
if ! apt update; then
    print_error "Ошибка при обновлении списка пакетов"
    exit 1
fi
print_success "Список пакетов обновлен"

print_step "Обновление установленных пакетов..."
apt upgrade -y
apt dist-upgrade -y
apt autoremove -y
apt autoclean
print_success "Система обновлена"

# Установка базовых пакетов
print_header "УСТАНОВКА БАЗОВЫХ ПАКЕТОВ"
packages=(
    curl wget git htop neofetch mc
    net-tools nmap tcpdump iotop
    unzip tar vim tmux screen
    rsync ncdu dnsutils resolvconf
    chrony fail2ban
)

for package in "${packages[@]}"; do
    print_step "Установка $package..."
    apt install -y "$package" && print_success "$package установлен" || print_error "Ошибка установки $package"
done

# Настройка локали
print_header "НАСТРОЙКА ЛОКАЛИ"
print_step "Установка русской локали..."
apt install -y language-pack-ru
locale-gen ru_RU.UTF-8
update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8
dpkg-reconfigure -f noninteractive locales
print_success "Локаль настроена"

# Настройка временной зоны
print_header "НАСТРОЙКА ВРЕМЕНИ"
print_step "Установка временной зоны Europe/Moscow..."
timedatectl set-timezone Europe/Moscow
print_success "Временная зона установлена"

# Настройка синхронизации времени
print_step "Настройка Chrony..."
systemctl enable chronyd
systemctl start chronyd
print_success "Chrony настроен"

# Настройка DNS
print_header "НАСТРОЙКА DNS"
print_step "Настройка systemd-resolved..."

# Размаскировка службы если она замаскирована
systemctl unmask systemd-resolved || true
systemctl stop systemd-resolved || true

# Создание конфигурации DNS
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
systemctl enable systemd-resolved
if ! systemctl restart systemd-resolved; then
    print_error "Ошибка запуска systemd-resolved, настройка альтернативного DNS..."
    # Альтернативная настройка через resolvconf
    print_step "Настройка resolvconf..."
    cat > /etc/resolvconf/resolv.conf.d/head << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    resolvconf -u
    print_success "Альтернативный DNS настроен"
else
    print_success "systemd-resolved настроен"
fi

# Настройка файрволла
print_header "НАСТРОЙКА ФАЙРВОЛЛА"
print_step "Настройка UFW..."
if command -v ufw >/dev/null 2>&1; then
    ufw status verbose > "$BACKUP_DIR/ufw_rules_backup"
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    print_success "UFW настроен"
fi

# Настройка SSH
print_header "НАСТРОЙКА SSH"
print_step "Настройка безопасности"
# Продолжение настройки SSH
cat >> /etc/ssh/sshd_config << EOF

# Дополнительные настройки безопасности
PermitRootLogin no
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
Protocol 2
AllowAgentForwarding no
AllowTcpForwarding no
LoginGraceTime 30
EOF

systemctl restart sshd
print_success "SSH настроен"

# Настройка fail2ban
print_header "НАСТРОЙКА FAIL2BAN"
print_step "Настройка защиты от брутфорса..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat >> /etc/fail2ban/jail.local << EOF

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600
findtime = 600
EOF

systemctl enable fail2ban
systemctl start fail2ban
print_success "Fail2ban настроен"

# Оптимизация системных параметров
print_header "ОПТИМИЗАЦИЯ СИСТЕМЫ"
print_step "Настройка системных параметров..."
cat >> /etc/sysctl.conf << EOF

# Оптимизация системы
# Сетевые параметры
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_max_tw_buckets = 720000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# Параметры безопасности
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Оптимизация памяти
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

sysctl -p
print_success "Системные параметры оптимизированы"

# Создание файла с информацией о системе
print_header "СОХРАНЕНИЕ ИНФОРМАЦИИ О СИСТЕМЕ"
print_step "Создание отчета..."

cat > /root/system_setup_info.txt << EOF
╔════════════════════════════════════════════════════════════════╗
║                  ИНФОРМАЦИЯ О НАСТРОЙКЕ СИСТЕМЫ                 ║
╚════════════════════════════════════════════════════════════════╝

Дата настройки: $(date)
Версия скрипта: $SCRIPT_VERSION
Автор: $SCRIPT_AUTHOR

СИСТЕМНАЯ ИНФОРМАЦИЯ
───────────────────
Hostname: $(hostname)
Версия ОС: $(lsb_release -d | cut -f2)
Ядро: $(uname -r)

СЕТЕВЫЕ НАСТРОЙКИ
────────────────
IP адреса: 
$(ip addr show | grep "inet " | awk '{print "  ▪ " $2}')

DNS серверы:
$(resolvectl status 2>/dev/null | grep "DNS Servers" | sed 's/^/  ▪ /' || cat /etc/resolv.conf | grep nameserver | sed 's/^/  ▪ /')

СТАТУС СЛУЖБ
───────────
▪ systemd-resolved: $(systemctl is-active systemd-resolved)
▪ fail2ban: $(systemctl is-active fail2ban)
▪ chronyd: $(systemctl is-active chronyd)
▪ ufw: $(systemctl is-active ufw)

ПРАВИЛА ФАЙРВОЛЛА
────────────────
$(ufw status verbose | sed 's/^/  /')

ПУТЬ К РЕЗЕРВНЫМ КОПИЯМ
───────────────────────
$BACKUP_DIR
EOF

print_success "Отчет сохранен в /root/system_setup_info.txt"

# Финальная информация
print_header "УСТАНОВКА ЗАВЕРШЕНА"
echo -e "${GREEN}Установка успешно завершена!${NC}"
echo -e "${CYAN}Backup directory:${NC} $BACKUP_DIR"
echo -e "${CYAN}Log file:${NC} $LOG_FILE"
echo -e "${CYAN}System info:${NC} /root/system_setup_info.txt"

# Запрос на перезагрузку
echo
read -p "Перезагрузить систему сейчас? (y/n): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    print_header "ПЕРЕЗАГРУЗКА"
    log "INFO" "Выполняется перезагрузка..."
    shutdown -r now
else
    print_warning "Перезагрузка отложена. Рекомендуется перезагрузить систему позже."
fi