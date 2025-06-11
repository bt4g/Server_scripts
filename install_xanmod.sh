#!/bin/bash

# Version: 1.2.1
# Author: gopnikgame
# Created: 2025-02-15 18:03:59 UTC
# Last Modified: 2025-06-11 16:20:00 UTC
# Description: XanMod kernel installation script with BBR3 optimization
# Repository: https://github.com/gopnikgame/Server_scripts
# License: MIT

set -euo pipefail

# Константы
readonly SCRIPT_VERSION="1.2.1"
readonly SCRIPT_AUTHOR="gopnikgame"
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-xanmod-bbr.conf"
readonly SCRIPT_PATH="/usr/local/sbin/xanmod_install"
readonly SERVICE_NAME="xanmod-install-continue"
readonly CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
readonly CURRENT_USER=$(whoami)

# Функция логирования
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m - $1" | tee -a "$LOG_FILE"
}

# Функция вывода заголовка
print_header() {
    echo -e "\n\033[1;32m=== $1 ===\033[0m\n" | tee -a "$LOG_FILE"
}

# Функция вывода ошибки
log_error() {
    echo -e "\033[1;31m[ОШИБКА] - $1\033[0m" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка наличия XanMod
check_xanmod() {
    if uname -r | grep -q "xanmod"; then
        local current_kernel
        current_kernel=$(uname -r)
        log "Обнаружено установленное ядро XanMod: $current_kernel"
        
        if [ -f "$STATE_FILE" ]; then
            log "Найден файл состояния установки. Продолжаем настройку..."
            configure_bbr
            remove_startup_service
            rm -f "$STATE_FILE"
            print_header "Установка успешно завершена!"
            echo -e "\nДля проверки работы BBR3 используйте команды:"
            echo -e "\033[1;36msysctl net.ipv4.tcp_congestion_control\033[0m"
            echo -e "\033[1;36msysctl net.core.default_qdisc\033[0m\n"
            exit 0
        else
            echo -e "\n\033[1;33mВнимание: Ядро XanMod уже установлено.\033[0m"
            read -rp $'Хотите переустановить? [y/N]: ' answer
            case $answer in
                [Yy]* ) 
                    log "Пользователь выбрал переустановку"
                    return 0
                    ;;
                * )
                    log "Установка отменена пользователем"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# Проверка операционной системы
check_os() {
    print_header "Проверка системы"
    
    # Сначала проверяем XanMod
    check_xanmod
    
    if [ ! -f /etc/os-release ]; then
        log_error "Файл /etc/os-release не найден"
        exit 1
    fi
    
    local os_id
    local os_name
    
    os_id=$(grep -E "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
    os_name=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case "$os_id" in
        debian|ubuntu)
            log "✓ Обнаружена поддерживаемая ОС: $os_name"
            ;;
        *)
            log_error "Операционная система $os_name не поддерживается"
            log_error "Поддерживаются только Debian и Ubuntu"
            exit 1
            ;;
    esac
    
    if [ "$(uname -m)" != "x86_64" ]; then
        log_error "Поддерживается только архитектура x86_64"
        exit 1
    fi
    
    log "✓ Архитектура системы: $(uname -m)"
}

# Проверка интернет-соединения
check_internet() {
    log "Проверка подключения к интернету..."
    if ! ping -c1 -W3 google.com &>/dev/null; then
        log_error "Нет подключения к интернету"
        exit 1
    fi
    log "✓ Подключение к интернету активно"
}

# Проверка свободного места
check_disk_space() {
    local required_space=2000
    local available_space
    available_space=$(df --output=avail -m / | awk 'NR==2 {print $1}')
    
    log "Проверка свободного места..."
    if (( available_space < required_space )); then
        log_error "Недостаточно свободного места (минимум 2 ГБ)"
        exit 1
    fi
    log "✓ Доступно $(( available_space / 1024 )) ГБ свободного места"
}

# Определение PSABI версии
get_psabi_version() {
    local level=1
    local flags
    flags=$(grep -m1 flags /proc/cpuinfo | cut -d ':' -f 2 | tr -d ' \n\t\r')
    
    if [[ $flags =~ avx512 ]]; then 
        # Для AVX-512 используем v3, так как метапакета x64v4 нет в репозитории
        level=3
        log "Обнаружена поддержка AVX-512, используется оптимизация x64v3 (максимальная поддерживаемая)"
    elif [[ $flags =~ avx2 ]]; then 
        level=3
    elif [[ $flags =~ sse4_2 ]]; then 
        level=2
    fi
    
    printf 'x64v%d' "$level"
}

# Функция для проверки доступности пакета
check_package_availability() {
    local package_name="$1"
    log "Проверка доступности пакета: $package_name..."
    
    # Проверка доступности метапакетов
    if apt-cache show "$package_name" 2>/dev/null | grep -q "Package: $package_name"; then
        log "✓ Пакет $package_name доступен в репозитории"
        echo "$package_name"
        return 0
    fi
    
    log "Пакет $package_name не найден, проверяем альтернативы..."
    
    # Проверка альтернативных версий
    if [[ "$package_name" == *"-x64v4" ]]; then
        local alt_package="${package_name/x64v4/x64v3}"
        log "Проверка наличия альтернативного пакета: $alt_package"
        
        if apt-cache show "$alt_package" 2>/dev/null | grep -q "Package: $alt_package"; then
            log "✓ Найден альтернативный пакет: $alt_package"
            echo "$alt_package"
            return 0
        fi
    elif [[ "$package_name" == *"-x64v3" ]]; then
        local alt_package="${package_name/x64v3/x64v2}"
        log "Проверка наличия альтернативного пакета: $alt_package"
        
        if apt-cache show "$alt_package" 2>/dev/null | grep -q "Package: $alt_package"; then
            log "✓ Найден альтернативный пакет: $alt_package"
            echo "$alt_package"
            return 0
        fi
    fi
    
    # Поиск метапакетов по списку
    log "Поиск доступных метапакетов..."
    local available_metapackages=$(apt-cache search "^linux-xanmod-" | grep -v "headers\|image" | awk '{print $1}')
    
    if [[ -n "$available_metapackages" ]]; then
        # Выбираем наиболее подходящий метапакет
        for meta in $available_metapackages; do
            if [[ "$meta" == *"$package_name"* || "$package_name" == *"$meta"* ]]; then
                log "✓ Найден подходящий метапакет: $meta"
                echo "$meta"
                return 0
            fi
        done
        
        # Если не нашли конкретного совпадения, используем первый доступный
        local first_meta=$(echo "$available_metapackages" | head -n1)
        log "✓ Используем доступный метапакет: $first_meta"
        echo "$first_meta"
        return 0
    fi
    
    # Если не нашли метапакеты, ищем конкретные пакеты ядра
    log "Поиск конкретных версий ядра..."
    local psabi_version="x64v3"
    
    if [[ "$package_name" =~ x64v([1-4]) ]]; then
        psabi_version=$(echo "$package_name" | grep -o "x64v[1-4]")
    fi
    
    # Поиск наиболее свежей версии ядра с заданным PSABI
    local latest_kernel=$(apt-cache search "linux-image-[0-9].*-${psabi_version}-xanmod[0-9]" | sort -Vr | head -n1 | awk '{print $1}')
    
    if [[ -n "$latest_kernel" ]]; then
        log "✓ Найдена конкретная версия ядра: $latest_kernel"
        echo "$latest_kernel"
        return 0
    fi
    
    # Попробуем найти хоть какую-то версию XanMod
    local any_xanmod=$(apt-cache search "linux-image.*xanmod" | sort -Vr | head -n1 | awk '{print $1}')
    
    if [[ -n "$any_xanmod" ]]; then
        log "✓ Найдена версия XanMod: $any_xanmod"
        echo "$any_xanmod"
        return 0
    fi
    
    # Вывод доступных пакетов в лог
    log "Доступные пакеты XanMod:"
    apt-cache search "xanmod" | tee -a "$LOG_FILE"
    
    # Если ничего не найдено, возвращаем пустую строку с ошибкой
    log_error "Не найдено подходящих пакетов XanMod"
    echo ""
}

# Выбор версии ядра
select_kernel_version() {
    local PSABI_VERSION
    PSABI_VERSION=$(get_psabi_version)
    
    {
        print_header "Выбор версии ядра XanMod"
        
        echo -e "\n\033[1;33mℹ️  Информация о системе:\033[0m"
        echo "----------------------------------------"
        echo -e "Текущая дата:      \033[1;36m$CURRENT_DATE\033[0m"
        echo -e "Пользователь:      \033[1;36m$CURRENT_USER\033[0m"
        echo -e "Текущее ядро:      \033[1;36m$(uname -r)\033[0m"
        echo -e "Оптимизация CPU:    \033[1;32m${PSABI_VERSION}\033[0m"
        echo -e "BBR3 поддержка:     \033[1;32mВключена\033[0m"
        echo "----------------------------------------"
        
        echo -e "\n\033[1;33m📦 Доступные версии ядра:\033[0m"
        echo "----------------------------------------"
        echo -e "\033[1;36m1)\033[0m linux-xanmod         \033[1;32m(Рекомендуется, 6.14)\033[0m"
        echo -e "\033[1;36m2)\033[0m linux-xanmod-edge    \033[1;33m(Тестовая, 6.15)\033[0m"
        echo -e "\033[1;36m3)\033[0m linux-xanmod-rt      \033[1;35m(RT, 6.12)\033[0m"
        echo -e "\033[1;36m4)\033[0m linux-xanmod-lts     \033[1;34m(LTS, 6.12)\033[0m"
        echo "----------------------------------------"
    } > /dev/tty

    read -rp $'\033[1;33mВыберите версию ядра (1-4, по умолчанию 1): \033[0m' choice < /dev/tty

    local KERNEL_PACKAGE
    case $choice in
        2) KERNEL_PACKAGE="linux-xanmod-edge";;
        3) KERNEL_PACKAGE="linux-xanmod-rt";;
        4) KERNEL_PACKAGE="linux-xanmod-lts";;
        *) KERNEL_PACKAGE="linux-xanmod";;
    esac

    if [[ $KERNEL_PACKAGE != "linux-xanmod-rt" ]]; then
        KERNEL_PACKAGE="${KERNEL_PACKAGE}-${PSABI_VERSION}"
    fi

    printf "%s" "$KERNEL_PACKAGE"
}

# Установка ядра
install_kernel() {
    print_header "Установка ядра XanMod"
    
    # Создаем директории для ключей и репозиториев
    mkdir -p /etc/apt/keyrings
    mkdir -p /etc/apt/sources.list.d
    
    if [ ! -f "/etc/apt/keyrings/xanmod-archive-keyring.gpg" ]; then
        log "Добавление репозитория XanMod..."
        if ! wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg; then
            log_error "Ошибка при добавлении ключа"
            exit 1
        fi
        
        if ! echo 'deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null; then
            log_error "Ошибка при добавлении репозитория"
            exit 1
        fi
        
        log "Обновление списка пакетов..."
        if ! apt-get update; then
            log_error "Ошибка при обновлении пакетов"
            exit 1
        fi
        log "✓ Репозиторий XanMod успешно добавлен"
    fi

    # Проверяем доступные метапакеты XanMod
    log "Проверка доступных пакетов XanMod..."
    local available_packages=$(apt-cache search "^linux-xanmod-" | grep -v "headers\|image" | sort)
    if [ -z "$available_packages" ]; then
        log_error "Не найдены метапакеты XanMod. Проверка отдельных пакетов ядра..."
        available_packages=$(apt-cache search "linux-image.*xanmod" | sort)
        
        if [ -z "$available_packages" ]; then
            log_error "Не найдены пакеты ядра XanMod. Возможно, репозиторий недоступен или неправильно настроен."
            log "Проверка доступности репозитория..."
            curl -I http://deb.xanmod.org
            exit 1
        fi
    fi
    
    log "Доступные пакеты XanMod:"
    echo "$available_packages" | tee -a "$LOG_FILE"

    # Выбор версии ядра
    log "Выбор версии ядра..."
    local KERNEL_PACKAGE
    KERNEL_PACKAGE=$(select_kernel_version)
    
    if [ -z "$KERNEL_PACKAGE" ]; then
        log_error "Ошибка: имя пакета пустое"
        exit 1
    fi

    log "Выбран пакет: $KERNEL_PACKAGE"
    
    # Проверяем наличие выбранного пакета
    if ! apt-cache show "$KERNEL_PACKAGE" >/dev/null 2>&1; then
        log_error "Пакет $KERNEL_PACKAGE не найден в репозитории"
        
        # Проверка альтернативных версий
        log "Поиск альтернативных версий..."
        
        # Сначала проверяем метапакеты без psABI суффикса
        local base_package
        if [[ "$KERNEL_PACKAGE" == *"-x64v"* ]]; then
            base_package="${KERNEL_PACKAGE%-x64v*}"
            log "Проверка базового пакета: $base_package"
            
            if apt-cache show "$base_package" >/dev/null 2>&1; then
                log "✓ Найден базовый пакет: $base_package"
                KERNEL_PACKAGE="$base_package"
            fi
        fi
        
        # Если и базовый пакет не найден, ищем другие версии psABI
        if ! apt-cache show "$KERNEL_PACKAGE" >/dev/null 2>&1; then
            local psabi_versions=("x64v3" "x64v2" "x64v1")
            
            for version in "${psabi_versions[@]}"; do
                if [[ "$KERNEL_PACKAGE" == *"-x64v"* ]]; then
                    local alt_package="${KERNEL_PACKAGE/-x64v[1-4]/-$version}"
                    log "Проверка альтернативной версии: $alt_package"
                    
                    if apt-cache show "$alt_package" >/dev/null 2>&1; then
                        log "✓ Найден альтернативный пакет: $alt_package"
                        KERNEL_PACKAGE="$alt_package"
                        break
                    fi
                fi
            done
        fi
        
        # Если все еще не найден пакет, ищем любой подходящий образ ядра
        if ! apt-cache show "$KERNEL_PACKAGE" >/dev/null 2>&1; then
            log "Поиск любого доступного ядра XanMod..."
            local kernel_type
            
            if [[ "$KERNEL_PACKAGE" == *"edge"* ]]; then
                kernel_type="edge"
            elif [[ "$KERNEL_PACKAGE" == *"rt"* ]]; then
                kernel_type="rt"
            elif [[ "$KERNEL_PACKAGE" == *"lts"* ]]; then
                kernel_type="lts"
            else
                kernel_type=""
            fi
            
            # Ищем последнюю версию образа ядра
            local latest_kernel
            if [ -n "$kernel_type" ]; then
                latest_kernel=$(apt-cache search "linux-image-.*-${kernel_type}-.*xanmod" | sort -Vr | head -n1 | awk '{print $1}')
            else
                latest_kernel=$(apt-cache search "linux-image-.*xanmod" | grep -v "edge\|rt\|lts" | sort -Vr | head -n1 | awk '{print $1}')
            fi
            
            if [ -n "$latest_kernel" ]; then
                log "✓ Найден образ ядра: $latest_kernel"
                KERNEL_PACKAGE="$latest_kernel"
            else
                # Крайний случай - выводим список и предлагаем выбрать вручную
                log_error "Не удалось автоматически выбрать пакет ядра"
                echo -e "\n\033[1;33mДоступные пакеты XanMod:\033[0m"
                apt-cache search "linux.*xanmod" | sort
                
                read -rp $'\033[1;33mВведите точное имя пакета для установки или нажмите Enter для выхода: \033[0m' manual_package
                
                if [ -n "$manual_package" ]; then
                    KERNEL_PACKAGE="$manual_package"
                    log "Выбран пакет вручную: $KERNEL_PACKAGE"
                else
                    log "Установка отменена пользователем"
                    exit 1
                fi
            fi
        fi
    fi

    log "Подготовка к установке пакета: $KERNEL_PACKAGE"
    echo -e "\n\033[1;33mУстановка пакета: ${KERNEL_PACKAGE}\033[0m"
    apt-get update -qq

    # Настройка параметров загрузки для BBR3
    log "Настройка параметров загрузки ядра..."
    if ! grep -q "tcp_congestion_control=bbr" /etc/default/grub; then
        cp /etc/default/grub /etc/default/grub.backup
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="tcp_congestion_control=bbr /' /etc/default/grub
        log "✓ Параметры загрузки обновлены"
    fi

    # Установка с явным указанием конфигурации GRUB
    export DEBIAN_FRONTEND=noninteractive
    
    # Определяем тип пакета и устанавливаем соответствующие пакеты
    if [[ "$KERNEL_PACKAGE" =~ ^linux-xanmod ]]; then
        # Установка метапакета
        log "Установка метапакета XanMod: $KERNEL_PACKAGE"
        if ! apt-get install -y "$KERNEL_PACKAGE" grub-pc; then
            log_error "Ошибка при установке метапакета. Попытка установки конкретных пакетов..."
            
            # Если метапакет не устанавливается, попробуем найти конкретную версию ядра
            local kernel_version
            local kernel_prefix
            
            if [[ "$KERNEL_PACKAGE" == *"-edge"* ]]; then
                kernel_prefix="edge"
            elif [[ "$KERNEL_PACKAGE" == *"-rt"* ]]; then
                kernel_prefix="rt"
            elif [[ "$KERNEL_PACKAGE" == *"-lts"* ]]; then
                kernel_prefix="lts"
            else
                kernel_prefix=""
            fi
            
            local psabi_version="x64v3"
            if [[ "$KERNEL_PACKAGE" == *"-x64v"* ]]; then
                psabi_version=$(echo "$KERNEL_PACKAGE" | grep -o "x64v[1-4]")
            fi
            
            # Ищем подходящий образ ядра
            local image_package
            if [ -n "$kernel_prefix" ]; then
                image_package=$(apt-cache search "linux-image-.*-${psabi_version}-.*${kernel_prefix}.*xanmod" | sort -Vr | head -n1 | awk '{print $1}')
            else
                image_package=$(apt-cache search "linux-image-.*-${psabi_version}-.*xanmod" | grep -v "edge\|rt\|lts" | sort -Vr | head -n1 | awk '{print $1}')
            fi
            
            if [ -n "$image_package" ]; then
                local headers_package="${image_package/image/headers}"
                log "Установка образа ядра: $image_package и заголовков: $headers_package"
                
                if ! apt-get install -y "$image_package" "$headers_package" grub-pc; then
                    log_error "Ошибка при установке ядра"
                    exit 1
                fi
            else
                log_error "Не удалось найти подходящие пакеты ядра"
                exit 1
            fi
        fi
    else
        # Установка конкретного образа ядра
        log "Установка конкретного образа ядра: $KERNEL_PACKAGE"
        local headers_package="${KERNEL_PACKAGE/linux-image/linux-headers}"
        
        if apt-cache show "$headers_package" >/dev/null 2>&1; then
            log "Установка ядра и заголовков: $KERNEL_PACKAGE, $headers_package"
            if ! apt-get install -y "$KERNEL_PACKAGE" "$headers_package" grub-pc; then
                log_error "Ошибка при установке ядра"
                exit 1
            fi
        else
            log "Заголовки не найдены, установка только образа ядра: $KERNEL_PACKAGE"
            if ! apt-get install -y "$KERNEL_PACKAGE" grub-pc; then
                log_error "Ошибка при установке ядра"
                exit 1
            fi
        fi
    fi

    log "Обновление конфигурации GRUB..."
    if ! update-grub; then
        log_error "Ошибка при обновлении GRUB"
        exit 1
    fi

    echo "kernel_installed" > "$STATE_FILE"
    log "✓ Ядро успешно установлено"
    
    # Показываем информацию о установленном ядре
    log "Установленные пакеты ядра XanMod:"
    dpkg -l | grep xanmod | tee -a "$LOG_FILE"
}

# Настройка BBR
configure_bbr() {
    print_header "Настройка TCP BBR3"
    
    if ! uname -r | grep -q "xanmod"; then
        log_error "Не обнаружено ядро XanMod"
        exit 1
    fi
    
    log "Применение оптимизированных сетевых настроек..."
    
    local temp_config
    temp_config=$(mktemp)
    
    cat > "$temp_config" <<EOF
# BBR3 core settings
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr

# TCP optimizations for XanMod
net.ipv4.tcp_ecn=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_low_latency=1

# Buffer settings optimized for 10Gbit+ networks
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.core.optmem_max=65536
net.ipv4.tcp_rmem=4096 1048576 67108864
net.ipv4.tcp_wmem=4096 1048576 67108864

# BBR3 specific optimizations
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_notsent_lowat=131072
net.core.netdev_max_backlog=16384
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1

# Additional XanMod optimizations
net.core.busy_read=50
net.core.busy_poll=50
net.ipv4.tcp_max_orphans=16384
EOF

    if ! sysctl -p "$temp_config" &>"$LOG_FILE"; then
        log_error "Ошибка применения настроек sysctl. Подробности:"
        cat "$LOG_FILE"
        rm -f "$temp_config"
        exit 1
    fi

    if ! cp "$temp_config" "$SYSCTL_CONFIG"; then
        log_error "Ошибка при копировании конфигурации"
        rm -f "$temp_config"
        exit 1
    fi

    rm -f "$temp_config"
    log "✓ Сетевые настройки применены"

    # Проверка загрузки модуля BBR
    if ! lsmod | grep -q "^tcp_bbr "; then
        log "Загрузка модуля tcp_bbr..."
        modprobe tcp_bbr
        if [ $? -ne 0 ]; then
            log_error "Ошибка загрузки модуля tcp_bbr"
            exit 1
        fi
    fi

    # Проверка версии BBR
    bbr_version=$(modinfo tcp_bbr | grep "^version:" | awk '{print $2}')
    if [[ "$bbr_version" == "3" ]]; then
        log "✓ Обнаружен BBR3 (версия модуля: $bbr_version)"
    else
        log_error "Неожиданная версия BBR: $bbr_version (ожидается 3)"
    fi
    
    echo -e "\n\033[1;33mВажно: BBR3 будет активирован после перезагрузки\033[0m"
    check_bbr_version
}

# Проверка версии BBR
check_bbr_version() {
    log "Проверка конфигурации сети..."
    
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    local bbr_version
    bbr_version=$(modinfo tcp_bbr 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "unknown")
    
    echo -e "\n\033[1;33mТекущая конфигурация:\033[0m"
    echo "----------------------------------------"
    echo -e "Алгоритм управления:    \033[1;32m$current_cc\033[0m"
    echo -e "Планировщик очереди:    \033[1;32m$current_qdisc\033[0m"
    echo -e "Версия BBR:             \033[1;32m$bbr_version\033[0m"
    echo -e "ECN статус:             \033[1;32m$(sysctl -n net.ipv4.tcp_ecn)\033[0m"
    echo "----------------------------------------"

    if [[ "$current_cc" == "bbr" && "$bbr_version" == "3" && "$current_qdisc" == "fq_pie" ]]; then
        echo -e "\n\033[1;32m✓ BBR3 правильно настроен и активен\033[0m"
    else
        echo -e "\n\033[1;31m⚠ BBR3 настроен некорректно\033[0m"
        echo -e "\nОжидаемые значения:"
        echo -e "- tcp_congestion_control: bbr"
        echo -e "- BBR версия: 3"
        echo -e "- default_qdisc: fq_pie"
    fi
}

# Создание сервиса автозапуска
create_startup_service() {
    log "Создание сервиса автозапуска..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=XanMod Kernel Installation Continuation
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH --continue
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    log "✓ Сервис автозапуска создан"
}

# Удаление сервиса автозапуска
remove_startup_service() {
    log "Очистка системы..."
    systemctl disable "${SERVICE_NAME}.service"
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    rm -f "$SCRIPT_PATH"
    log "✓ Временные файлы удалены"
}

# Главная функция
main() {
    if [[ "${1:-}" == "--continue" ]] && [ -f "$STATE_FILE" ]; then
        configure_bbr
        remove_startup_service
        rm -f "$STATE_FILE"
        print_header "Установка успешно завершена!"
        echo -e "\nДля проверки работы BBR3 используйте команды:"
        echo -e "\033[1;36msysctl net.ipv4.tcp_congestion_control\033[0m"
        echo -e "\033[1;36msysctl net.core.default_qdisc\033[0m\n"
        exit 0
    fi

    print_header "Установка XanMod Kernel v$SCRIPT_VERSION"
    check_root
    check_os
    check_internet
    check_disk_space
    install_kernel
    create_startup_service
    echo -e "\n\033[1;33mУстановка завершена. Система будет перезагружена через 5 секунд...\033[0m"
    sleep 5
    reboot
}

# Запуск скрипта
main "$@"