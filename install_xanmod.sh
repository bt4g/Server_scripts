#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-15 06:30:03 UTC
# Last Modified: 2025-02-15 06:30:03 UTC
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
readonly CURRENT_DATE="2025-02-15 06:30:03"
readonly CURRENT_USER="gopnikgame"

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
        level=4
    elif [[ $flags =~ avx2 ]]; then 
        level=3
    elif [[ $flags =~ sse4_2 ]]; then 
        level=2
    fi
    
    printf 'x64v%d' "$level"
}

# Выбор версии ядра
select_kernel_version() {
    local PSABI_VERSION
    PSABI_VERSION=$(get_psabi_version)
    
    {
        print_header "Выбор версии ядра XanMod"
        
        echo -e "\n\033[1;33mℹ️  Информация о системе:\033[0m"
        echo "----------------------------------------"
        echo -e "Текущая дата:      \033[1;36m2025-02-15 06:31:16\033[0m"
        echo -e "Пользователь:      \033[1;36mgopnikgame\033[0m"
        echo -e "Текущее ядро:      \033[1;36m$(uname -r)\033[0m"
        echo -e "Оптимизация CPU:    \033[1;32m${PSABI_VERSION}\033[0m"
        echo "----------------------------------------"
        
        echo -e "\n\033[1;33m📦 Доступные версии ядра:\033[0m"
        echo "----------------------------------------"
        echo -e "\033[1;36m1)\033[0m linux-xanmod         \033[1;32m(Рекомендуется)\033[0m"
        echo -e "\033[1;36m2)\033[0m linux-xanmod-edge    \033[1;33m(Тестовая)\033[0m"
        echo -e "\033[1;36m3)\033[0m linux-xanmod-rt      \033[1;35m(RT)\033[0m"
        echo -e "\033[1;36m4)\033[0m linux-xanmod-lts     \033[1;34m(LTS)\033[0m"
        echo "----------------------------------------"
        
        echo -e "\n\033[1;33m💡 Описание версий:\033[0m"
        echo -e "\033[1;32m1) Стабильная\033[0m      - Оптимальный баланс производительности и стабильности"
        echo -e "\033[1;33m2) Edge\033[0m            - Новейшие функции и обновления (может быть нестабильной)"
        echo -e "\033[1;35m3) RT\033[0m              - Оптимизирована для задач реального времени"
        echo -e "\033[1;34m4) LTS\033[0m             - Версия с долгосрочной поддержкой"
        
        echo -e "\n\033[1;33m🔧 Рекомендации по выбору:\033[0m"
        echo -e "• Для домашних ПК и серверов   → \033[1;32mСтабильная (1)\033[0m"
        echo -e "• Для энтузиастов              → \033[1;33mEdge (2)\033[0m"
        echo -e "• Для аудио/видео обработки    → \033[1;35mRT (3)\033[0m"
        echo -e "• Для рабочих станций          → \033[1;34mLTS (4)\033[0m"
        
        echo -e "\n\033[1;32mℹ️  Все версии будут установлены с оптимизацией ${PSABI_VERSION}\033[0m"
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

    {
        echo -e "\n\033[1;32mВыбрана версия:\033[0m ${KERNEL_PACKAGE}"
        echo "----------------------------------------"
    } > /dev/tty

    printf "%s" "$KERNEL_PACKAGE"
}

# Установка ядра
install_kernel() {
    print_header "Установка ядра XanMod"
    
    # Проверка и создание директорий
    mkdir -p /etc/apt/trusted.gpg.d
    mkdir -p /etc/apt/sources.list.d
    
    if [ ! -f "/etc/apt/trusted.gpg.d/xanmod-kernel.gpg" ]; then
        log "Добавление репозитория XanMod..."
        if ! curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg; then
            log_error "Ошибка при добавлении ключа"
            exit 1
        fi
        
        if ! echo 'deb [signed-by=/etc/apt/trusted.gpg.d/xanmod-kernel.gpg] http://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-kernel.list; then
            log_error "Ошибка при добавлении репозитория"
            exit 1
        fi
        
        if ! apt-get update -qq; then
            log_error "Ошибка при обновлении пакетов"
            exit 1
        fi
        log "✓ Репозиторий XanMod успешно добавлен"
    fi

    local KERNEL_PACKAGE
    KERNEL_PACKAGE=$(select_kernel_version | tr -d '\n\r' | tr -d '[:space:]')

    if [ -z "$KERNEL_PACKAGE" ]; then
        log_error "Ошибка: имя пакета пустое"
        exit 1
    fi

    echo -e "\n\033[1;33mУстановка пакета: ${KERNEL_PACKAGE}\033[0m"
    apt-get update -qq

    if ! apt-cache show "$KERNEL_PACKAGE" >/dev/null 2>&1; then
        log_error "Пакет $KERNEL_PACKAGE не найден в репозитории"
        echo -e "\nДоступные пакеты XanMod:"
        apt-cache search linux-xanmod
        exit 1
    fi

    # Установка с явным указанием конфигурации GRUB
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get install -y "$KERNEL_PACKAGE" grub-pc; then
        log_error "Ошибка при установке ядра"
        exit 1
    fi

    log "Обновление конфигурации GRUB..."
    if ! update-grub; then
        log_error "Ошибка при обновлении GRUB"
        exit 1
    fi

    echo "kernel_installed" > "$STATE_FILE"
    log "✓ Ядро успешно установлено"
}

# Настройка BBR
configure_bbr() {
    print_header "Настройка TCP BBR3"
    
    # Проверка наличия ядра XanMod
    if ! uname -r | grep -q "xanmod"; then
        log_error "Не обнаружено ядро XanMod"
        exit 1
    fi
    
    # Проверка прав доступа к sysctl
    if [ ! -w "/etc/sysctl.d" ]; then
        log_error "Нет прав на запись в /etc/sysctl.d"
        exit 1
    fi
    
    log "Применение оптимизированных сетевых настроек..."
    
    # Создание временного файла конфигурации
    local temp_config
    temp_config=$(mktemp)
    
    # Запись настроек во временный файл
    cat > "$temp_config" <<EOF
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

    # Проверка синтаксиса конфигурации
    if ! sysctl -p "$temp_config" &>/dev/null; then
        log_error "Ошибка в синтаксисе конфигурации sysctl"
        rm -f "$temp_config"
        exit 1
    fi

    # Копирование проверенной конфигурации
    if ! cp "$temp_config" "$SYSCTL_CONFIG"; then
        log_error "Ошибка при копировании конфигурации"
        rm -f "$temp_config"
        exit 1
    fi

    # Удаление временного файла
    rm -f "$temp_config"

    # Применение настроек с подробным выводом ошибок
    if ! sysctl --system 2>"$LOG_FILE"; then
        log_error "Ошибка применения настроек sysctl. Подробности в $LOG_FILE"
        log_error "$(cat "$LOG_FILE")"
        exit 1
    fi

    log "✓ Сетевые настройки применены"
    
    # Проверка применения настроек
    if ! check_bbr_version; then
        log_error "Настройки BBR3 не были применены корректно"
        exit 1
    fi
}

# Проверка версии BBR
check_bbr_version() {
    log "Проверка конфигурации BBR..."
    
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "unknown")
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    
    echo -e "\n\033[1;33mТекущая конфигурация:\033[0m"
    echo "----------------------------------------"
    echo -e "Алгоритм управления:    \033[1;32m$current_cc\033[0m"
    echo -e "Доступные алгоритмы:    \033[1;36m$available_cc\033[0m"
    echo -e "Планировщик очереди:    \033[1;32m$current_qdisc\033[0m"
    echo "----------------------------------------"
    
    if [[ "$current_cc" != "bbr3" ]]; then
        log_error "BBR3 не активирован!"
        return 1
    fi

    if [[ "$current_qdisc" != "fq_pie" ]]; then
        log "⚠️  Предупреждение: Планировщик очереди отличается от рекомендуемого (fq_pie)"
    else
        log "✓ Конфигурация BBR3 активна"
    fi

    return 0
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