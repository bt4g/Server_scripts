#!/bin/bash
set -e

# Метаданные скрипта
SCRIPT_VERSION="1.0.15"
SCRIPT_DATE="2025-05-14 13:51:12"
SCRIPT_AUTHOR="gopnikgame"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
    
    # Очистка системы после обновления
    log "INFO" "Очистка после обновления..."
    
    # Удаление устаревших пакетов
    print_step "Удаление неиспользуемых пакетов..."
    apt autoremove -y
    
    # Очистка только устаревших пакетов
    print_step "Очистка устаревших архивов пакетов..."
    apt autoclean
    
    # Проверка свободного места после очистки
    local free_space_before_clean=$(df -h / | awk 'NR==2 {print $4}')
    local free_space_after_clean=$(df -h / | awk 'NR==2 {print $4}')
    
    print_success "Система успешно обновлена и очищена."
    log "INFO" "Система успешно обновлена и очищена. Освобождено места: $free_space_after_clean (было: $free_space_before_clean)"
}


# Настройка DNS через systemd-resolved
configure_dns() {
    log "INFO" "Настройка DNS через systemd-resolved..."
    
    # Проверка, работаем ли мы в контейнере или виртуализированной среде
    check_virtualization() {
        log "INFO" "Проверка среды выполнения..."
        
        if [ -f "/.dockerenv" ] || grep -q "docker\|lxc\|container" /proc/1/cgroup 2>/dev/null; then
            log "INFO" "Обнаружено выполнение в контейнере"
            return 0
        elif command -v systemd-detect-virt >/dev/null && systemd-detect-virt -q 2>/dev/null; then
            virt_type=$(systemd-detect-virt 2>/dev/null)
            log "INFO" "Обнаружена виртуализация: $virt_type"
            return 0
        fi
        
        log "INFO" "Среда выполнения: физический хост"
        return 1
    }
    
    # Проверяем среду выполнения
    is_virtualized=0
    check_virtualization && is_virtualized=1

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

    # Создание новой конфигурации resolved
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
    
    # Получение первого IP из выбранного DNS без DoH суффикса
    primary_ip=$(echo "$primary_dns" | cut -d'#' -f1 | awk '{print $1}')
    
    # Проверяем, можно ли изменить resolv.conf
    if [ -f "/etc/resolv.conf" ]; then
        # Проверка на immutable бит
        if command -v lsattr >/dev/null 2>&1; then
            log "INFO" "Проверка атрибутов /etc/resolv.conf..."
            lsattr_output=$(lsattr /etc/resolv.conf 2>/dev/null || echo "")
            
            if echo "$lsattr_output" | grep -q "i"; then
                log "INFO" "Обнаружен immutable бит на /etc/resolv.conf. Снимаем..."
                chattr -i /etc/resolv.conf 2>/dev/null || true
            fi
        fi
        
        # Сохраняем резервную копию
        if [ ! -L "/etc/resolv.conf" ]; then
            backup_file "/etc/resolv.conf"
            log "INFO" "Сохранена резервная копия /etc/resolv.conf"
        fi
        
        # Пытаемся удалить существующий файл
        rm -f "/etc/resolv.conf" 2>/dev/null || true
    fi
    
    # Если удалось удалить старый файл, создаем символьную ссылку
    if [ ! -f "/etc/resolv.conf" ] && ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; then
        log "INFO" "✓ Символическая ссылка /etc/resolv.conf успешно создана."
    else
        log "WARNING" "⚠ Не удалось создать символическую ссылку /etc/resolv.conf."
        
        # Если символьная ссылка не удалась, и мы в виртуализированной среде
        if [ $is_virtualized -eq 1 ]; then
            log "INFO" "Используем альтернативные методы настройки DNS в виртуализированной среде..."
            
            # Используем resolvectl для настройки DNS, если он доступен
            if command -v resolvectl >/dev/null 2>&1; then
                log "INFO" "Настройка DNS через resolvectl..."
                
                # Разбиваем DNS-строки на отдельные серверы
                IFS=' ' read -ra PRIMARY_SERVERS <<< "$primary_dns"
                
                # Получаем список активных интерфейсов, кроме lo
                interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
                
                # Если список интерфейсов пуст, используем хотя бы основной интерфейс
                if [ -z "$interfaces" ]; then
                    interfaces=$(ip route | grep default | awk '{print $5}')
                fi
                
                # Применяем для всех интерфейсов
                for iface in $interfaces; do
                    for dns_server in "${PRIMARY_SERVERS[@]}"; do
                        dns_ip=$(echo "$dns_server" | cut -d'#' -f1)
                        resolvectl dns "$iface" "$dns_ip" >/dev/null 2>&1 || true
                    done
                    resolvectl domain "$iface" "~." >/dev/null 2>&1 || true
                    log "INFO" "Настроен DNS для интерфейса: $iface"
                done
            fi
            
            # Как запасной вариант, используем resolvconf, если он доступен
            if command -v resolvconf >/dev/null 2>&1; then
                log "INFO" "Применение настроек через resolvconf..."
                
                mkdir -p /etc/resolvconf/resolv.conf.d
                cat > /etc/resolvconf/resolv.conf.d/head << EOF
# Настроено скриптом ubuntu_pre_install.sh
# Дата: $(date "+%Y-%m-%d %H:%M:%S")
nameserver $primary_ip
nameserver 127.0.0.53
options edns0 trust-ad
search .
EOF
                
                resolvconf -u
                log "INFO" "Настройки применены через resolvconf"
            fi
            
            # Если ничего не помогло, пытаемся создать напрямую
            if [ ! -f "/etc/resolv.conf" ] || ! grep -q "$primary_ip" /etc/resolv.conf; then
                log "INFO" "Пытаемся создать файл resolv.conf напрямую..."
                
                # Создаем временный файл и затем перемещаем его
                temp_file=$(mktemp)
                cat > "$temp_file" << EOF
# Создано скриптом ubuntu_pre_install.sh
# Дата: $(date "+%Y-%m-%d %H:%M:%S")
nameserver $primary_ip
nameserver 127.0.0.53
options edns0 trust-ad
search .
EOF
                
                # Пробуем скопировать файл вместо перемещения
                cat "$temp_file" > /etc/resolv.conf 2>/dev/null || true
                rm -f "$temp_file"
                
                if grep -q "$primary_ip" /etc/resolv.conf; then
                    log "INFO" "✓ Файл /etc/resolv.conf успешно создан."
                else
                    log "WARNING" "⚠ Не удалось настроить /etc/resolv.conf напрямую."
                    log "INFO" "Попробуйте выполнить настройку DNS вручную после перезагрузки."
                    
                    # Сохраняем настройки в файл для ручного применения
                    echo -e "${YELLOW}Выбранные DNS-серверы:${NC}" > /root/dns_settings.txt
                    echo "Основной: $primary_dns" >> /root/dns_settings.txt
                    echo "Резервный 1: $fallback_dns1" >> /root/dns_settings.txt
                    echo "Резервный 2: $fallback_dns2" >> /root/dns_settings.txt
                    echo -e "\nДля ручной настройки используйте команду:" >> /root/dns_settings.txt
                    echo "echo 'nameserver $primary_ip' > /etc/resolv.conf" >> /root/dns_settings.txt
                    
                    log "INFO" "Сохранены настройки DNS в файл /root/dns_settings.txt"
                fi
            fi
        else
            # Для физического хоста
            log "INFO" "Настройка DNS для физического хоста..."
            
            # Перезапускаем systemd-resolved даже при ошибках
            systemctl restart systemd-resolved || true
            
            # Проверяем, работает ли системный резолвер
            nslookup google.com 127.0.0.53 >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log "INFO" "✓ Системный резолвер (127.0.0.53) работает."
            else
                log "WARNING" "⚠ Системный резолвер не работает. Настраиваем напрямую..."
                
                # Пытаемся создать файл resolv.conf напрямую
                cat > /etc/resolv.conf.new << EOF
# Создано скриптом ubuntu_pre_install.sh
# Дата: $(date "+%Y-%m-%d %H:%M:%S")
nameserver $primary_ip
options edns0
EOF
                
                # Пытаемся заменить файл
                cat /etc/resolv.conf.new > /etc/resolv.conf 2>/dev/null || true
                rm -f /etc/resolv.conf.new
            fi
        fi
    fi

    # Перезапуск службы DNS
    log "INFO" "Перезапуск systemd-resolved..."
    systemctl restart systemd-resolved || true
    
    # Дополнительная проверка resolvectl
    if command -v resolvectl &> /dev/null; then
        log "INFO" "Статус DNS (resolvectl):"
        resolvectl status | grep -E "DNS Server|DNS Domain" || true
    fi
    
    log "INFO" "DNS настроен."

    # Проверка работы DNS
    log "INFO" "Проверка работы DNS..."
    if host google.com > /dev/null 2>&1; then
        log "INFO" "✓ DNS работает корректно."
    else
        log "WARNING" "⚠ Проблемы с DNS. Проверьте конфигурацию."
        log "WARNING" "Рекомендуется перезагрузить систему после завершения скрипта."
        
        # Дополнительная диагностика
        log "INFO" "Выполнение диагностики DNS..."
        log "INFO" "Содержимое /etc/resolv.conf:"
        cat /etc/resolv.conf || true
        
        log "INFO" "Попытка ручного разрешения имен через выбранный DNS-сервер:"
        if command -v dig &> /dev/null; then
            dig @"$primary_ip" google.com +short || true
        elif command -v nslookup &> /dev/null; then
            nslookup google.com "$primary_ip" || true
        fi
        
        # Сообщаем о возможных причинах проблемы
        log "WARNING" "Возможные причины проблем с DNS:"
        log "WARNING" "1. Блокировка DNS-трафика провайдером или файрволлом"
        log "WARNING" "2. Проблемы с настройкой сети или маршрутизацией"
        log "WARNING" "3. Ограничения в виртуализированной среде"
        # Предлагаем решение
        log "INFO" "Попробуйте следующее:"
        log "INFO" "1. Перезапустите систему"
        log "INFO" "2. Проверьте соединение с интернетом: ping 8.8.8.8"
        log "INFO" "3. Проверьте работу DNS вручную: nslookup google.com $primary_ip"
        
        # Сохраняем информацию в лог-файл
        echo "==== Диагностика DNS $(date) ====" >> "$LOG_FILE"
        echo "Выбранный DNS: $primary_ip" >> "$LOG_FILE"
        echo "Содержимое /etc/resolv.conf:" >> "$LOG_FILE"
        cat /etc/resolv.conf >> "$LOG_FILE" 2>&1 || echo "Не удалось прочитать /etc/resolv.conf" >> "$LOG_FILE"
        echo "Результат проверки:" >> "$LOG_FILE"
        host google.com >> "$LOG_FILE" 2>&1 || echo "Ошибка при проверке host google.com" >> "$LOG_FILE"
        echo "=================================" >> "$LOG_FILE"
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

# Смена пароля root
change_root_password() {
    log "INFO" "Смена пароля пользователя root..."
    
    # Проверка, что команда passwd доступна
    if ! command -v passwd &> /dev/null; then
        log "ERROR" "Команда passwd не найдена. Невозможно сменить пароль."
        return 1
    fi
    
    echo -e "${YELLOW}=== Смена пароля пользователя root ===${NC}"
    echo "ВНИМАНИЕ: Пароль не будет отображаться при вводе."
    echo "Если вы планируете использовать только SSH-ключи, пароль можно сделать сложным."

    # Запрашиваем новый пароль
    local password_changed=0
    local attempt=1
    local max_attempts=3

    while [ $password_changed -eq 0 ] && [ $attempt -le $max_attempts ]; do
        echo ""
        echo "Попытка $attempt из $max_attempts:"
        
        # Используем временный файл для смены пароля
        temp_file=$(mktemp)
        chmod 600 "$temp_file"
        
        read -s -p "Введите новый пароль: " password
        echo ""
        read -s -p "Повторите новый пароль: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            log "WARNING" "Пароли не совпадают. Попробуйте снова."
            attempt=$((attempt+1))
            continue
        fi
        
        if [ -z "$password" ]; then
            log "WARNING" "Пароль не может быть пустым. Попробуйте снова."
            attempt=$((attempt+1))
            continue
        fi
        
        # Проверка сложности пароля
        if [ ${#password} -lt 8 ]; then
            echo -e "${YELLOW}Предупреждение: Пароль короче 8 символов.${NC}"
            read -p "Продолжить со слабым паролем? (y/n): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                attempt=$((attempt+1))
                continue
            fi
        fi
        
        # Меняем пароль
        echo "root:$password" | chpasswd 2> "$temp_file"
        
        if [ $? -eq 0 ]; then
            log "INFO" "Пароль пользователя root успешно изменен."
            password_changed=1
        else
            log "ERROR" "Ошибка при смене пароля: $(cat "$temp_file")"
            attempt=$((attempt+1))
        fi
        
        rm -f "$temp_file"
    done
    
    if [ $password_changed -eq 0 ]; then
        log "ERROR" "Не удалось сменить пароль после $max_attempts попыток."
        return 1
    fi
    
    return 0
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

# Проверка статуса IPv6
check_ipv6_status() {
    if [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" -eq 0 ]; then
        return 0  # IPv6 включен
    else
        return 1  # IPv6 выключен
    fi
}

# Включение IPv6
enable_ipv6() {
    log "INFO" "Включение IPv6..."
    
    if check_ipv6_status; then
        log "INFO" "IPv6 уже включен."
        print_success "IPv6 уже включен."
        return 0
    fi

    print_step "Включение IPv6..."
    interface_name=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)

    # Создаем резервную копию sysctl.conf
    backup_file "/etc/sysctl.conf"

    # Удаляем старые настройки IPv6
    sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
    sed -i "/net.ipv6.conf.$interface_name.disable_ipv6/d" /etc/sysctl.conf

    # Добавляем новые настройки для включения IPv6
    echo "# Включение IPv6" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
    echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> /etc/sysctl.conf
    echo "net.ipv6.conf.$interface_name.disable_ipv6 = 0" >> /etc/sysctl.conf

    # Применяем изменения
    sysctl -p > /dev/null 2>&1

    log "INFO" "IPv6 успешно включен."
    print_success "IPv6 успешно включен."
    
    # Информация о сетевых интерфейсах с IPv6
    print_step "Проверка конфигурации IPv6..."
    ip -6 addr show | grep -v "scope host" || echo "IPv6 адреса пока не назначены."
    
    log "INFO" "Рекомендуется перезагрузить систему для полного применения изменений."
    print_step "Рекомендуется перезагрузить систему для полного применения изменений."
    
    return 0
}

# Отключение IPv6
disable_ipv6() {
    log "INFO" "Отключение IPv6..."
    
    if ! check_ipv6_status; then
        log "INFO" "IPv6 уже отключен."
        print_success "IPv6 уже отключен."
        return 0
    fi

    print_step "Отключение IPv6..."
    interface_name=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)

    # Создаем резервную копию sysctl.conf
    backup_file "/etc/sysctl.conf"

    # Удаляем старые настройки IPv6
    sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
    sed -i "/net.ipv6.conf.$interface_name.disable_ipv6/d" /etc/sysctl.conf

    # Добавляем новые настройки для отключения IPv6
    echo "# Отключение IPv6" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.$interface_name.disable_ipv6 = 1" >> /etc/sysctl.conf

    # Применяем изменения
    sysctl -p > /dev/null 2>&1

    log "INFO" "IPv6 успешно отключен."
    print_success "IPv6 успешно отключен."
    
    log "INFO" "Рекомендуется перезагрузить систему для полного применения изменений."
    print_step "Рекомендуется перезагрузить систему для полного применения изменений."
    
    return 0
}

# Управление IPv6
manage_ipv6() {
    while true; do
        print_header "Управление IPv6"
        
        # Проверяем текущий статус IPv6
        if check_ipv6_status; then
            echo -e "Текущий статус: ${GREEN}IPv6 включен${NC}"
            echo
            echo -e "1) ${YELLOW}Отключить IPv6${NC}"
        else
            echo -e "Текущий статус: ${RED}IPv6 отключен${NC}"
            echo
            echo -e "1) ${GREEN}Включить IPv6${NC}"
        fi
        
        echo -e "0) ${BLUE}Вернуться в предыдущее меню${NC}"
        echo
        
        read -p "Выберите действие [0-1]: " choice
        
        case $choice in
            0)
                return 0
                ;;
            1)
                if check_ipv6_status; then
                    disable_ipv6
                else
                    enable_ipv6
                fi
                ;;
            *)
                print_error "Неверный выбор"
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}


# Функция перезагрузки
reboot_system() {
    log "INFO" "Подготовка к перезагрузке системы..."
    
    # Проверка, запущен ли скрипт в интерактивном режиме
    if tty -s; then
        echo -e "${YELLOW}=== Перезагрузка системы ===${NC}"
        echo "Все несохраненные данные будут потеряны."
        read -p "Вы уверены, что хотите перезагрузить систему сейчас? (y/n): " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Выполняется перезагрузка..."
            print_success "Перезагрузка системы..."
            shutdown -r now
        else
            log "INFO" "Перезагрузка отменена пользователем."
            print_step "Перезагрузка отменена."
        fi
    else
        log "WARNING" "Скрипт запущен в неинтерактивном режиме. Перезагрузка не может быть выполнена."
        print_error "Невозможно выполнить перезагрузку в неинтерактивном режиме."
    fi
}


# Главное меню
show_menu() {
    while true; do
        print_header "НАСТРОЙКА UBUNTU v${SCRIPT_VERSION}"
        echo -e "${YELLOW}Выберите действие:${NC}"
        echo
        
        local i=1
        
        # Выводим пункты меню
        echo -e "$i) ${GREEN}Установить зависимости и утилиты${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Обновить систему${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Настроить DNS${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Настроить файрволл (UFW)${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Сменить пароль root${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Настроить SSH${NC}"
        ((i++))
        echo -e "$i) ${GREEN}Применить системные твики${NC}"
        ((i++))
        echo -e "$i) ${YELLOW}Выполнить все задачи автоматически${NC}"
        ((i++))
        echo -e "$i) ${YELLOW}Управление IPv6${NC}"
        ((i++))
        echo -e "$i) ${YELLOW}Перезагрузить систему${NC}"
        ((i++))
        echo -e "0) ${RED}Выход${NC}"
        echo
        
        read -p "Выберите опцию [0-$((i-1))]: " choice
        echo

        case $choice in
            0)
                print_success "До свидания!"
                exit 0
                ;;
            1)
                install_dependencies
                ;;
            2)
                update_system
                ;;
            3)
                configure_dns
                ;;
            4)
                configure_firewall
                ;;
            5)
                change_root_password
                ;;
            6)
                configure_ssh
                ;;
            7)
                apply_system_tweaks
                ;;
            8)
                install_dependencies
                update_system
                configure_dns
                configure_firewall
                change_root_password
                configure_ssh
                apply_system_tweaks
                ;;
            9)
                manage_ipv6
                ;;
            10)
                reboot_system
                ;;
            *)
                print_error "Неверный выбор"
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
    done
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