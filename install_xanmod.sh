#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-15 04:21:59 UTC
# Last Modified: 2025-02-15 04:21:59 UTC
# Description: XanMod kernel installation script with BBR3 optimization
# Repository: https://github.com/gopnikgame/Server_scripts
# License: MIT

set -euo pipefail

# Константы
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_AUTHOR="gopnikgame"
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-xanmod-bbr.conf"
readonly SCRIPT_PATH="/usr/local/sbin/xanmod_install"
readonly SERVICE_NAME="xanmod-install-continue"

# Перенаправление вывода в лог
exec > >(tee -a "$LOG_FILE") 2>&1

# Функция логирования
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m - $1"
}

# Функция вывода заголовка
print_header() {
    echo -e "\n\033[1;32m=== $1 ===\033[0m\n"
}

# Функция вывода ошибки
log_error() {
    echo -e "\033[1;31m[ОШИБКА] - $1\033[0m"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка операционной системы
check_os() {
    print_header "Проверка системы"
    
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
    flags=$(grep -m1 flags /proc/cpuinfo | cut -d ':' -f 2)
    if [[ $flags =~ avx512 ]]; then 
        level=4
    elif [[ $flags =~ avx2 ]]; then 
        level=3
    elif [[ $flags =~ sse4_2 ]]; then 
        level=2
    fi
    echo "x64v$level"
}

# Функция выбора версии ядра
select_kernel_version() {
    print_header "Выбор версии ядра XanMod"
    local PSABI_VERSION
    PSABI_VERSION=$(get_psabi_version)
    log "Рекомендуемая оптимизация для вашего CPU: ${PSABI_VERSION}"
    
    echo -e "\n\033[1;33mДоступные версии ядра:\033[0m"
    echo "----------------------------------------"
    echo -e "\033[1;36m1)\033[0m linux-xanmod         - Стабильная версия (рекомендуется)"
    echo -e "\033[1;36m2)\033[0m linux-xanmod-edge    - Версия с новейшими функциями"
    echo -e "\033[1;36m3)\033[0m linux-xanmod-rt      - Версия с поддержкой реального времени"
    echo -e "\033[1;36m4)\033[0m linux-xanmod-lts     - Версия с долгосрочной поддержкой"
    echo "----------------------------------------"
    echo -e "Все версии будут установлены с оптимизацией \033[1;32m${PSABI_VERSION}\033[0m\n"
    
    local choice
    read -rp $'\033[1;33mВаш выбор (1-4, по умолчанию 1): \033[0m' choice
    local KERNEL_PACKAGE
    case $choice in
        2)
            KERNEL_PACKAGE="linux-xanmod-edge-${PSABI_VERSION}"
            ;;
        3)
            KERNEL_PACKAGE="linux-xanmod-rt-${PSABI_VERSION}"
            ;;
        4)
            KERNEL_PACKAGE="linux-xanmod-lts-${PSABI_VERSION}"
            ;;
        *)
            KERNEL_PACKAGE="linux-xanmod-${PSABI_VERSION}"
            ;;
    esac
    
    echo -e "\n\033[1;32mВыбрана версия:\033[0m $KERNEL_PACKAGE"
    echo "----------------------------------------"
    
    echo "$KERNEL_PACKAGE"
}

# Установка ядра
install_kernel() {
    print_header "Установка ядра XanMod"
    
    if [ ! -f "/etc/apt/trusted.gpg.d/xanmod-kernel.gpg" ]; then
        log "Добавление репозитория XanMod..."
        curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg || {
            log_error "Ошибка при добавлении ключа"
            exit 1
        }
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/xanmod-kernel.gpg] http://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-kernel.list || {
            log_error "Ошибка при добавлении репозитория"
            exit 1
        }
        apt-get update -qq || {
            log_error "Ошибка при обновлении пакетов"
            exit 1
        }
        log "✓ Репозиторий XanMod успешно добавлен"
    fi

    local KERNEL_PACKAGE
    KERNEL_PACKAGE=$(select_kernel_version)

    echo -e "\n\033[1;33mУстановка пакета: $KERNEL_PACKAGE\033[0m"
    apt-get install -y "$KERNEL_PACKAGE" || {
        log_error "Ошибка при установке ядра"
        exit 1
    }

    log "Обновление конфигурации GRUB..."
    update-grub || {
        log_error "Ошибка при обновлении GRUB"
        exit 1
    }

    echo "kernel_installed" > "$STATE_FILE"
    log "✓ Ядро успешно установлено"
}

# Настройка BBR
configure_bbr() {
    print_header "Настройка TCP BBR3"
    
    if ! uname -r | grep -q "xanmod"; then
        log_error "Не обнаружено ядро XanMod"
        exit 1
    fi
    
    log "Применение оптимизированных сетевых настроек..."
    cat > "$SYSCTL_CONFIG" <<EOF
# BBR настройки
net.ipv4.tcp_congestion_control = bbr3
net.core.default_qdisc = fq_pie
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_low_latency = 1

# Оптимизация сетевого стека
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 67108864
net.ipv4.tcp_wmem = 4096 1048576 67108864
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_notsent_lowat = 131072
EOF

    sysctl --system >/dev/null 2>&1 || { 
        log_error "Ошибка применения настроек sysctl"
        exit 1
    }
    log "✓ Сетевые настройки применены"

    check_bbr_version
}

# Проверка версии BBR
check_bbr_version() {
    log "Проверка конфигурации BBR..."
    
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc)
    
    echo -e "\n\033[1;33mТекущая конфигурация:\033[0m"
    echo "----------------------------------------"
    echo -e "Алгоритм управления:    \033[1;32m$current_cc\033[0m"
    echo -e "Доступные алгоритмы:    \033[1;36m$available_cc\033[0m"
    echo -e "Планировщик очереди:    \033[1;32m$current_qdisc\033[0m"
    echo "----------------------------------------"
    
    if [[ "$current_cc" != "bbr3" ]]; then
        log_error "BBR3 не активирован!"
        exit 1
    fi

    if [[ "$current_qdisc" != "fq_pie" ]]; then
        log "⚠️  Предупреждение: Планировщик очереди отличается от рекомендуемого (fq_pie)"
    else
        log "✓ Конфигурация BBR3 активна"
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
    local continue_installation=0
    
    if [[ "${1:-}" == "--continue" ]]; then
        continue_installation=1
    fi

    if [ "$continue_installation" -eq 1 ]; then
        if [ -f "$STATE_FILE" ]; then
            configure_bbr
            remove_startup_service
            rm -f "$STATE_FILE"
            print_header "Установка успешно завершена!"
            echo -e "\nДля проверки работы BBR3 используйте команды:"
            echo -e "\033[1;36msysctl net.ipv4.tcp_congestion_control\033[0m"
            echo -e "\033[1;36msysctl net.core.default_qdisc\033[0m\n"
        else
            log_error "Файл состояния не найден"
            exit 1
        fi
    else
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
    fi
}

# Запуск скрипта
main "$@"