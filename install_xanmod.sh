#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-14 22:38:54 UTC
# Description: XanMod kernel installation script with BBR3 optimization

set -euo pipefail
exec > >(tee -a "/var/log/xanmod_install.log") 2>&1

# Константы
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-xanmod-bbr.conf"
readonly SCRIPT_PATH="/usr/local/sbin/xanmod_install"
readonly SERVICE_NAME="xanmod-install-continue"
readonly VERSION="1.0.0"

# Функция логирования
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - $message" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Ошибка: Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка интернет-соединения
check_internet() {
    if ! ping -c1 -W3 google.com &>/dev/null; then
        log "Ошибка: Нет подключения к интернету"
        exit 1
    fi
}

# Проверка свободного места
check_disk_space() {
    local required_space=2000  # 2GB в MB
    local available_space
    available_space=$(df --output=avail -m / | awk 'NR==2 {print $1}')
    
    if (( available_space < required_space )); then
        log "Ошибка: Недостаточно свободного места (минимум 2 ГБ)"
        exit 1
    fi
}

# Определение доступных версий ядра
get_available_kernels() {
    log "Получение списка доступных версий ядра..."
    apt-get update -qq || { log "Ошибка при обновлении списка пакетов"; exit 1; }
    
    local kernels
    kernels=$(apt-cache search linux-xanmod | grep '^linux-xanmod' | cut -d ' ' -f 1 | grep -v 'headers\|image')
    
    if [ -z "$kernels" ]; then
        log "Ошибка: Не удалось получить список доступных версий"
        exit 1
    fi
    
    echo "$kernels"
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
    log "Выбор версии ядра XanMod"
    local PSABI_VERSION
    PSABI_VERSION=$(get_psabi_version)
    log "Рекомендуемая PSABI версия для вашего процессора: ${PSABI_VERSION}"
    
    echo -e "\nДоступные версии ядра XanMod:"
    echo "1) linux-xanmod-${PSABI_VERSION} (Стабильная версия)"
    echo "2) linux-xanmod-edge-${PSABI_VERSION} (Версия с новейшими функциями)"
    echo "3) linux-xanmod-rt-${PSABI_VERSION} (Версия с поддержкой реального времени)"
    echo "4) linux-xanmod-lts-${PSABI_VERSION} (Версия с долгосрочной поддержкой)"
    echo "5) Показать все доступные версии"
    
    local choice
    read -rp "Выберите версию ядра (1-5, по умолчанию 1): " choice
    
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
        5)
            echo -e "\nВсе доступные версии:"
            local all_versions
            mapfile -t all_versions < <(get_available_kernels)
            local i=1
            for version in "${all_versions[@]}"; do
                echo "$i) $version"
                ((i++))
            done
            
            local max=$((${#all_versions[@]}))
            read -rp "Выберите версию (1-$max): " subchoice
            
            if [[ "$subchoice" =~ ^[0-9]+$ ]] && [ "$subchoice" -ge 1 ] && [ "$subchoice" -le $max ]; then
                KERNEL_PACKAGE="${all_versions[$((subchoice-1))]}"
            else
                log "Неверный выбор. Используется стандартная версия."
                KERNEL_PACKAGE="linux-xanmod-${PSABI_VERSION}"
            fi
            ;;
        *)
            KERNEL_PACKAGE="linux-xanmod-${PSABI_VERSION}"
            ;;
    esac
    
    echo "$KERNEL_PACKAGE"
}

# Установка ядра
install_kernel() {
    log "Начало установки ядра Xanmod..."
    
    if [ ! -f "/etc/apt/trusted.gpg.d/xanmod-kernel.gpg" ]; then
        log "Добавление ключа и репозитория XanMod..."
        curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg || {
            log "Ошибка при добавлении ключа"
            exit 1
        }
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/xanmod-kernel.gpg] http://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-kernel.list || {
            log "Ошибка при добавлении репозитория"
            exit 1
        }
        apt-get update || {
            log "Ошибка при обновлении пакетов"
            exit 1
        }
    fi

    local KERNEL_PACKAGE
    KERNEL_PACKAGE=$(select_kernel_version)

    log "Установка пакета: $KERNEL_PACKAGE"
    apt-get install -y "$KERNEL_PACKAGE" || {
        log "Ошибка при установке ядра"
        exit 1
    }

    log "Обновление конфигурации GRUB..."
    update-grub || {
        log "Ошибка при обновлении GRUB"
        exit 1
    }

    echo "kernel_installed" > "$STATE_FILE"
    log "Ядро успешно установлено. Требуется перезагрузка."
}

# Настройка BBR
configure_bbr() {
    log "Настройка TCP BBR..."
    
    # Проверка текущего ядра на XanMod
    if ! uname -r | grep -q "xanmod"; then
        log "Ошибка: Не обнаружено ядро XanMod"
        exit 1
    fi
    
    # Создаем конфигурационный файл для sysctl
    cat > "$SYSCTL_CONFIG" <<EOF
# BBR
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

    # Применяем настройки
    sysctl --system || { log "Ошибка применения настроек sysctl"; exit 1; }

    # Проверяем активацию BBR3
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc)

    if [[ "$current_cc" != "bbr3" ]]; then
        log "Ошибка: BBR3 не активирован! Текущий алгоритм: $current_cc"
        return 1
    fi

    if [[ "$current_qdisc" != "fq_pie" ]]; then
        log "Предупреждение: Планировщик очереди не fq_pie (текущий: $current_qdisc)"
    fi

    log "Настройка TCP BBR3 завершена успешно"
    log "Текущий алгоритм: $current_cc"
    log "Текущий планировщик очереди: $current_qdisc"
    
    return 0
}

# Проверка версии BBR
check_bbr_version() {
    log "Проверка версии BBR..."
    
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc)
    
    log "Текущий алгоритм управления перегрузкой: $current_cc"
    log "Доступные алгоритмы: $available_cc"
    log "Текущий планировщик очереди: $current_qdisc"
    
    case "$current_cc" in
        "bbr3")
            log "Используется BBR3"
            ;;
        "bbr2")
            log "Используется BBR2"
            ;;
        "bbr")
            log "Используется BBR1"
            ;;
        *)
            log "BBR не используется. Текущий алгоритм: $current_cc"
            ;;
    esac
}

# Очистка системы
system_cleanup() {
    log "Начало очистки системы..."
    apt-get autoremove --purge -y || { log "Ошибка при выполнении apt-get autoremove --purge"; exit 1; }
    log "Очистка системы завершена успешно"
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

    cp "$0" "$SCRIPT_PATH" || {
        log "Ошибка: Не удалось скопировать скрипт в $SCRIPT_PATH"
        exit 1
    }
    
    chmod +x "$SCRIPT_PATH" || {
        log "Ошибка: Не удалось установить права на исполнение для $SCRIPT_PATH"
        exit 1
    }
    
    systemctl daemon-reload || {
        log "Ошибка: Не удалось перезагрузить systemd"
        exit 1
    }
    
    systemctl enable "${SERVICE_NAME}.service" || {
        log "Ошибка: Не удалось включить сервис ${SERVICE_NAME}"
        exit 1
    }
    
    log "Сервис автозапуска успешно создан"
}

# Удаление сервиса автозапуска
remove_startup_service() {
    log "Удаление сервиса автозапуска..."
    if systemctl is-enabled "${SERVICE_NAME}.service" &>/dev/null; then
        systemctl disable "${SERVICE_NAME}.service"
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    [ -f "$SCRIPT_PATH" ] && rm -f "$SCRIPT_PATH"
    log "Сервис автозапуска удален"
}

# Главная функция
main() {
    local continue_installation=0
    
    if [[ "${1:-}" == "--continue" ]]; then
        continue_installation=1
    fi

    # Начальные проверки
    check_root
    check_internet
    check_disk_space
    check_os

    if [[ -f "$STATE_FILE" ]]; then
        case $(cat "$STATE_FILE") in
            "kernel_installed")
                log "Завершающий этап: Настройка BBR3"
                configure_bbr
                check_bbr_version
                system_cleanup
                rm -f "$STATE_FILE"
                remove_startup_service
                log "Установка успешно завершена!"
                ;;
        esac
    else
        log "Начало установки..."
        install_kernel
        create_startup_service
        log "Перезагрузка системы..."
        reboot
    fi
}

# Запуск скрипта
main "$@"