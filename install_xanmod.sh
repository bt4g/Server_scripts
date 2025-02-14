#!/bin/bash

set -euo pipefail
exec > >(tee -a "/var/log/xanmod_install.log") 2>&1

# Константы
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-bbr.conf"
readonly SCRIPT_PATH="/usr/local/sbin/xanmod_install"
readonly SERVICE_NAME="xanmod-install-continue"
readonly TEMP_SCRIPT="/tmp/xanmod_install_temp.sh"

# Функция логирования
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Ошибка: Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка загруженного ядра
check_kernel() {
    local current_kernel=$(uname -r)
    
    if [[ "$current_kernel" != *"xanmod"* ]]; then
        log "ВНИМАНИЕ: Система не загружена на ядре Xanmod. Текущее ядро: $current_kernel"
        return 1
    fi
    log "Текущее ядро: $current_kernel - это ядро XanMod"
    return 0
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
    local available_space=$(df --output=avail -m / | awk 'NR==2 {print $1}')
    
    if (( available_space < required_space )); then
        log "Ошибка: Недостаточно свободного места (минимум 2 ГБ)"
        exit 1
    fi
}

# Проверка ОС
check_os() {
    if ! grep -E -q "Ubuntu|Debian" /etc/os-release; then
        log "Ошибка: Этот скрипт поддерживает только Ubuntu и Debian"
        exit 1
    fi
    if grep -q "Ubuntu" /etc/os-release; then
        readonly DISTRO="ubuntu"
    else
        readonly DISTRO="debian"
    fi
}

# Проверка архитектуры
check_architecture() {
    if [ "$(uname -m)" != "x86_64" ]; then
        log "Ошибка: Поддерживается только x86_64 архитектура"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    local deps=(awk grep apt-get software-properties-common curl gpg)
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "Установка недостающей зависимости: $dep"
            apt-get install -y "$dep" || { log "Ошибка при установке $dep"; exit 1; }
        fi
    done
}

# Обработчик прерываний
cleanup() {
    if [[ "${1:-}" != "reboot" ]]; then
        log "Скрипт прерван. Очистка временных файлов..."
        rm -f "$STATE_FILE"
        rm -f "$TEMP_SCRIPT"
    fi
    exit 1
}

trap cleanup INT TERM EXIT

# Определение PSABI версии
get_psabi_version() {
    local level=1
    local flags=$(grep -m1 flags /proc/cpuinfo | cut -d ':' -f 2)
    if [[ $flags =~ avx512 ]]; then level=4
    elif [[ $flags =~ avx2 ]]; then level=3
    elif [[ $flags =~ sse4_2 ]]; then level=2
    fi
    echo "x64v$level"
}

# Определение доступных версий ядра
get_available_kernels() {
    log "Получение списка доступных версий ядра..."
    apt-get update -qq || { log "Ошибка при обновлении списка пакетов"; exit 1; }
    
    local versions=$(apt-cache search linux-xanmod | grep '^linux-xanmod' | cut -d ' ' -f 1 | grep -v 'headers\|image')
    
    if [ -z "$versions" ]; then
        log "Ошибка: Не удалось получить список доступных версий"
        exit 1
    fi
    
    echo "$versions"
}

# Функция выбора версии ядра
select_kernel_version() {
    log "Выбор версии ядра XanMod"
    PSABI_VERSION=$(get_psabi_version)
    log "Рекомендуемая PSABI версия для вашего процессора: ${PSABI_VERSION}"
    
    echo -e "\nДоступные версии ядра XanMod:"
    echo "1) linux-xanmod-${PSABI_VERSION} (Стабильная версия)"
    echo "2) linux-xanmod-edge-${PSABI_VERSION} (Версия с новейшими функциями)"
    echo "3) linux-xanmod-rt-${PSABI_VERSION} (Версия с поддержкой реального времени)"
    echo "4) linux-xanmod-lts-${PSABI_VERSION} (Версия с долгосрочной поддержкой)"
    echo "5) Показать все доступные версии"
    
    local choice
    read -p "Выберите версию ядра (1-5, по умолчанию 1): " choice
    
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
            local all_versions=($(get_available_kernels))
            local i=1
            for version in "${all_versions[@]}"; do
                echo "$i) $version"
                ((i++))
            done
            
            local max=$((${#all_versions[@]}))
            read -p "Выберите версию (1-$max): " subchoice
            
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
    
    log "Выбрана версия ядра: $KERNEL_PACKAGE"
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

    cp "$0" "$SCRIPT_PATH" 2>/dev/null || {
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
    [ -f "$TEMP_SCRIPT" ] && rm -f "$TEMP_SCRIPT"
    log "Сервис автозапуска удален"
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

    select_kernel_version

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

# Обновление системы
system_update() {
    log "Начало обновления системы..."
    apt-get update || { log "Ошибка при выполнении apt-get update"; exit 1; }
    apt-get autoclean -y || { log "Ошибка при выполнении apt-get autoclean"; exit 1; }
    apt-get autoremove -y || { log "Ошибка при выполнении apt-get autoremove"; exit 1; }
    log "Обновление системы завершено успешно"
}

# Настройка BBR
configure_bbr() {
    log "Настройка TCP BBR..."
    echo "net.core.default_qdisc=fq" > "$SYSCTL_CONFIG"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_CONFIG"
    sysctl --system || { log "Ошибка применения настроек"; exit 1; }

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') != "bbr" ]]; then
        log "Ошибка: BBR не активирован!"
        exit 1
    fi
    log "Настройка BBR завершена успешно"
}

# Очистка системы
system_cleanup() {
    log "Начало очистки системы..."
    apt-get autoremove --purge -y || { log "Ошибка при выполнении apt-get autoremove --purge"; exit 1; }
    remove_startup_service
    log "Очистка системы завершена успешно"
}

# Главная функция
main() {
    local continue_installation=0
    
    if [[ "${1:-}" == "--continue" ]]; then
        continue_installation=1
    fi

    check_root
    check_internet
    check_disk_space
    check_os
    check_architecture
    check_dependencies

    if [[ -f "$STATE_FILE" ]]; then
        case $(cat "$STATE_FILE") in
            "update_complete")
                log "Продолжение после обновления системы..."
                check_kernel || true
                install_kernel
                create_startup_service
                trap 'cleanup reboot' EXIT
                log "Перезагрузка системы..."
                reboot
                ;;
            "kernel_installed")
                log "Завершающий этап: Настройка BBR"
                if check_kernel; then
                    configure_bbr
                    system_cleanup
                    rm -f "$STATE_FILE"
                    log "Установка успешно завершена!"
                else
                    log "Ошибка: Система не загружена на ядре XanMod"
                    exit 1
                fi
                ;;
        esac
    elif [[ $continue_installation -eq 0 ]]; then
        log "Начало установки..."
        system_update
        echo "update_complete" > "$STATE_FILE"
        create_startup_service
        trap 'cleanup reboot' EXIT
        log "Перезагрузка системы..."
        reboot
    fi
}

# Запуск скрипта
if [ ! -t 0 ]; then
    # Если скрипт запущен через pipe
    tee "$TEMP_SCRIPT" > /dev/null
    if [ ! -f "$TEMP_SCRIPT" ]; then
        echo "Ошибка: Не удалось создать временный файл"
        exit 1
    fi
    chmod +x "$TEMP_SCRIPT"
    if [ -x "$TEMP_SCRIPT" ]; then
        exec "$TEMP_SCRIPT" "$@"
    else
        echo "Ошибка: Не удалось сделать временный файл исполняемым"
        exit 1
    fi
else
    # Прямой запуск скрипта
    main "$@"
fi