#!/bin/bash
set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.13"
SCRIPT_DATE="2025-03-02 13:51:12"
SCRIPT_AUTHOR="gopnikgame"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Константы
BACKUP_DIR="/root/config_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/system_setup.log"
MIN_FREE_SPACE_KB=2097152  # 2GB в килобайтах

# Создаем директорию для резервных копий и логов
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

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
        systemctl unmask systemd-resolved || true
        systemctl restart systemd-resolved || true
    fi
    exit 1
}

# Установка обработчика ошибок
trap rollback ERR

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
        # Проверяем, что директория для бэкапа существует
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
            log "INFO" "Создана директория для резервных копий: $BACKUP_DIR"
        fi
        
        # Копируем файл
        cp "$src" "$BACKUP_DIR/" || { log "ERROR" "Не удалось создать резервную копию: $src"; exit 1; }
        log "INFO" "Создана резервная копия файла: $src"
    else
        log "WARNING" "Файл не найден для резервного копирования: $src"
    fi
}

# Установка зависимостей
install_dependencies() {
    log "INFO" "Обновление списка пакетов и установка зависимостей..."
    apt update
    apt install -y \
        curl wget git htop neofetch mc \
        net-tools nmap tcpdump iotop \
        unzip tar vim tmux screen \
        rsync ncdu dnsutils resolvconf \
        whois ufw openssh-server
}

# Обновление системы
update_system() {
    log "INFO" "Обновление системы..."
    apt update
    apt upgrade -y
    apt dist-upgrade -y
    log "INFO" "Система успешно обновлена."
}

# Настройка DNS через systemd-resolved
configure_dns() {
    log "INFO" "Настройка DNS через systemd-resolved..."

    # Проверка состояния systemd-resolved
    if systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
        log "INFO" "systemd-resolved уже включен."
    else
        log "INFO" "Размаскировка и включение systemd-resolved..."
        systemctl unmask systemd-resolved || true
        systemctl enable systemd-resolved || true
    fi

    # Создание резервной копии текущей конфигурации
    if [ -f "/etc/systemd/resolved.conf" ]; then
        backup_file "/etc/systemd/resolved.conf"
    fi

    # Объявление массивов DNS-серверов
    declare -A DNS_PROVIDERS
    DNS_PROVIDERS=(
        ["Google"]="8.8.8.8#dns.google 8.8.4.4#dns.google"
        ["Cloudflare"]="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com"
        ["AdGuard"]="94.140.14.14#dns.adguard.com 94.140.15.15#dns.adguard.com"
    )

    # Показать пользователю меню выбора DNS
    echo -e "\n${YELLOW}=== Выбор основного DNS провайдера ===${NC}"
    echo "1. Google DNS      (8.8.8.8, 8.8.4.4)"
    echo "2. Cloudflare DNS  (1.1.1.1, 1.0.0.1)"
    echo "3. AdGuard DNS     (94.140.14.14, 94.140.15.15)"
    echo ""
    read -p "Выберите основной DNS провайдер [1-3, по умолчанию 1]: " dns_choice

    # Определение основного и резервных DNS на основе выбора
    local primary_dns
    local fallback_dns1
    local fallback_dns2

    case "$dns_choice" in
        2)  # Cloudflare как основной
            primary_dns="${DNS_PROVIDERS["Cloudflare"]}"
            fallback_dns1="${DNS_PROVIDERS["Google"]}"
            fallback_dns2="${DNS_PROVIDERS["AdGuard"]}"
            log "INFO" "Выбран Cloudflare DNS в качестве основного."
            ;;
        3)  # AdGuard как основной
            primary_dns="${DNS_PROVIDERS["AdGuard"]}"
            fallback_dns1="${DNS_PROVIDERS["Google"]}"
            fallback_dns2="${DNS_PROVIDERS["Cloudflare"]}"
            log "INFO" "Выбран AdGuard DNS в качестве основного."
            ;;
        *)  # Google как основной (по умолчанию)
            primary_dns="${DNS_PROVIDERS["Google"]}"
            fallback_dns1="${DNS_PROVIDERS["Cloudflare"]}"
            fallback_dns2="${DNS_PROVIDERS["AdGuard"]}"
            log "INFO" "Выбран Google DNS в качестве основного."
            ;;
    esac

    # Создание новой конфигурации
    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
# Основной DNS
DNS=$primary_dns
FallbackDNS=$fallback_dns1 $fallback_dns2
Domains=~.
DNSOverTLS=yes
DNSSEC=yes

# Кеширование DNS
Cache=yes
CacheFromLocalhost=yes
DNSStubListener=yes
EOF

    # Проверка и настройка resolv.conf
    log "INFO" "Настройка /etc/resolv.conf..."
    
    # Сохраняем оригинальный resolv.conf
    if [ -f "/etc/resolv.conf" ]; then
        # Если это не ссылка, делаем резервную копию
        if [ ! -L "/etc/resolv.conf" ]; then
            backup_file "/etc/resolv.conf"
            log "INFO" "Сохранена резервная копия /etc/resolv.conf"
        fi
        
        # Удаляем существующий файл или ссылку
        rm -f "/etc/resolv.conf"
    fi
    
    # Создаем новую символическую ссылку
    if ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; then
        log "INFO" "✓ Символическая ссылка /etc/resolv.conf успешно создана."
    else
        log "WARNING" "⚠ Не удалось создать символическую ссылку /etc/resolv.conf."
        log "WARNING" "Пытаемся создать файл напрямую..."
        
        # Если не удалось создать ссылку, создаем файл с настройками напрямую
        cat > /etc/resolv.conf << EOF
# Создано скриптом ubuntu_pre_install.sh
# Дата: $(date "+%Y-%m-%d %H:%M:%S")
# Внимание: этот файл не является символической ссылкой на systemd-resolved

nameserver 127.0.0.53
options edns0 trust-ad
search .
EOF
        log "INFO" "✓ Файл /etc/resolv.conf создан напрямую."
    fi

    # Перезапуск службы DNS
    log "INFO" "Перезапуск systemd-resolved..."
    systemctl restart systemd-resolved

    # Дополнительная проверка resolvectl
    if command -v resolvectl &> /dev/null; then
        log "INFO" "Статус DNS (resolvectl):"
        resolvectl status
    fi
    
    log "INFO" "DNS успешно настроен."

    # Проверка работы DNS
    log "INFO" "Проверка работы DNS..."
    if host google.com > /dev/null 2>&1; then
        log "INFO" "✓ DNS работает корректно."
    else
        log "WARNING" "⚠ Проблемы с DNS. Проверьте конфигурацию."
        
        # Дополнительная диагностика
        log "INFO" "Выполнение диагностики DNS..."
        log "INFO" "Содержимое /etc/resolv.conf:"
        cat /etc/resolv.conf
        
        log "INFO" "Попытка ручного разрешения имен через серверы DNS:"
        if command -v dig &> /dev/null; then
            dig @94.140.14.14 google.com +short
            dig @8.8.8.8 google.com +short
        elif command -v nslookup &> /dev/null; then
            nslookup google.com 94.140.14.14
            nslookup google.com 8.8.8.8
        fi
    fi
   }
# Настройка файрволла (UFW)
configure_firewall() {
    log "INFO" "Настройка UFW..."

    # Блокировка IP-адресов из AS61280 (IPv4 и IPv6)
    log "INFO" "Получение списка IP-адресов для блокировки (AS61280)..."
    blocked_ips=$(whois -h whois.radb.net -- '-i origin AS61280' | grep -E '^route|^route6' | awk '{print $2}')
    if [ -z "$blocked_ips" ]; then
        log "WARNING" "Не удалось получить IP-адреса для блокировки."
    else
        log "INFO" "Блокировка IP-адресов из AS61280..."
        for ip in $blocked_ips; do
            ufw deny from "$ip" to any
            log "INFO" "Заблокирован IP-адрес: $ip"
        done
    fi

    # Основные правила UFW
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    yes | ufw enable
    log "INFO" "UFW успешно настроен."
}

# Настройка SSH
configure_ssh() {
    log "INFO" "Настройка безопасности SSH..."

    # Проверка наличия службы SSH
    if ! systemctl is-active --quiet ssh; then
        log "INFO" "Служба SSH не найдена. Установка OpenSSH..."
        apt install -y openssh-server
    fi

    # Создание директории .ssh и файла authorized_keys
    if [ ! -d "/root/.ssh" ]; then
        log "INFO" "Создание директории /root/.ssh..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
    fi

    if [ ! -f "/root/.ssh/authorized_keys" ]; then
        log "INFO" "Создание файла /root/.ssh/authorized_keys..."
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
    fi

    # Проверка наличия публичного ключа в authorized_keys
    if [ -s "/root/.ssh/authorized_keys" ]; then
        log "INFO" "Публичный ключ уже настроен в /root/.ssh/authorized_keys. Пропускаем шаг добавления ключа."
    else
        log "INFO" "Для продолжения настройки SSH требуется ваш публичный ключ."
        log "INFO" "Публичный ключ обычно находится в файле ~/.ssh/id_rsa.pub или ~/.ssh/id_ed25519.pub."
        log "INFO" "Пример публичного ключа:"
        log "INFO" "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArV1... user@hostname"
        read -p "Введите ваш публичный ключ SSH: " public_key

        # Проверка валидности публичного ключа
        if [[ -z "$public_key" || ! "$public_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            log "ERROR" "Некорректный публичный ключ. Убедитесь, что вы ввели его правильно."
            exit 1
        fi

        # Добавление публичного ключа в authorized_keys
        echo "$public_key" >> /root/.ssh/authorized_keys
        log "INFO" "Публичный ключ успешно добавлен в /root/.ssh/authorized_keys."
    fi

    # Настройка параметров SSH
    update_ssh_config() {
        local key="$1"
        local value="$2"
        if ! grep -q "^$key" /etc/ssh/sshd_config; then
            echo "$key $value" >> /etc/ssh/sshd_config
        else
            sed -i "s/^$key.*/$key $value/" /etc/ssh/sshd_config
        fi
    }

    update_ssh_config "PermitRootLogin" "prohibit-password"
    update_ssh_config "PasswordAuthentication" "no"
    update_ssh_config "X11Forwarding" "no"
    update_ssh_config "MaxAuthTries" "3"
    update_ssh_config "Protocol" "2"
    update_ssh_config "AllowAgentForwarding" "no"
    update_ssh_config "AllowTcpForwarding" "no"
    update_ssh_config "LoginGraceTime" "30"

    # Перезапуск службы SSH
    systemctl restart ssh
    log "INFO" "Служба SSH перезапущена. Парольная аутентификация отключена."
}

# Системные твики
apply_system_tweaks() {
    log "INFO" "Применение системных твиков..."

    # Оптимизация TCP/IP стека
    cat >> /etc/sysctl.conf << EOF
# Оптимизация сети
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_max_tw_buckets = 720000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
EOF
    sysctl -p
    log "INFO" "Системные твики применены."
}

# Главное меню
show_menu() {
    clear
    echo -e "${YELLOW}=== Главное меню ===${NC}"
    echo "1. Установить зависимости и утилиты"
    echo "2. Обновить систему"
    echo "3. Настроить DNS"
    echo "4. Настроить файрволл (UFW)"
    echo "5. Настроить SSH"
    echo "6. Применить системные твики"
    echo "7. Выполнить все задачи автоматически"
    echo "8. Выйти"
    echo ""
    read -p "Выберите пункт меню (1-8): " choice

    case "$choice" in
        1) install_dependencies ;;
        2) update_system ;;
        3) configure_dns ;;
        4) configure_firewall ;;
        5) configure_ssh ;;
        6) apply_system_tweaks ;;
        7) 
            install_dependencies
            update_system
            configure_dns
            configure_firewall
            configure_ssh
            apply_system_tweaks
            ;;
        8) exit 0 ;;
        *) echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}" ; sleep 2 ; show_menu ;;
    esac
}

# Запуск главного меню
show_menu

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