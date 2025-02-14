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

# Обработчик прерываний
cleanup() {
    if [[ "${1:-}" != "reboot" ]]; then
        log "Скрипт прерван. Очистка временных файлов..."
        rm -f "$STATE_FILE"
        rm -f "$TEMP_SCRIPT"
    fi
    exit 1
}
trap 'cleanup' INT TERM EXIT

# Создание сервиса автозапуска
create_startup_service() {
    log "Создание сервиса автозапуска..."
    
    # Определяем исходный скрипт
    local source_script
    if [ -f "$TEMP_SCRIPT" ]; then
        source_script="$TEMP_SCRIPT"
    else
        source_script="$0"
    fi

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

    # Копируем скрипт в системную директорию
    if ! cp "$source_script" "$SCRIPT_PATH" 2>/dev/null; then
        log "Ошибка: Не удалось скопировать скрипт в $SCRIPT_PATH"
        exit 1
    }
    
    chmod +x "$SCRIPT_PATH" || {
        log "Ошибка: Не удалось установить права на исполнение для $SCRIPT_PATH"
        exit 1
    }
    
    # Активируем сервис
    if ! systemctl daemon-reload; then
        log "Ошибка: Не удалось перезагрузить systemd"
        exit 1
    }
    
    if ! systemctl enable "${SERVICE_NAME}.service"; then
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

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Ошибка: Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка загруженного ядра
check_kernel() {
    local installed_kernel=$(ls /boot/vmlinuz-* 2>/dev/null | grep "xanmod" | sort -V | tail -n1 | awk -F'-' '{print $2"-"$3}')
    local current_kernel=$(uname -r)
    
    if [[ "$installed_kernel" != "" && "$installed_kernel" != "$current_kernel" ]]; then
        log "ВНИМАНИЕ: Система не загружена на ядре Xanmod. Текущее ядро: $current_kernel"
        return 1
    fi
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
    local deps=(awk grep apt-get)
    if [[ "$DISTRO" == "ubuntu" ]]; then
        deps+=(add-apt-repository)
    else
        deps+=(curl gpg)
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "Установка недостающей зависимости: $dep"
            apt-get install -y "$dep" || { log "Ошибка при установке $dep"; exit 1; }
        fi
    done
}

# Обновление системы
system_update() {
    log "Начало обновления системы..."
    apt-get update || { log "Ошибка при выполнении apt-get update"; exit 1; }
    apt-get autoclean -y || { log "Ошибка при выполнении apt-get autoclean"; exit 1; }
    apt-get autoremove -y || { log "Ошибка при выполнении apt-get autoremove"; exit 1; }
    log "Обновление системы завершено успешно"
}

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

# Установка ядра
install_kernel() {
    log "Начало установки ядра Xanmod..."
    PSABI_VERSION=$(get_psabi_version)
    log "Определена PSABI версия: $PSABI_VERSION"

    # Добавление репозитория
    if [[ "$DISTRO" == "ubuntu" ]]; then
        if ! grep -q "^deb .*/xanmod/kernel" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
            log "Добавление PPA для Ubuntu..."
            add-apt-repository -y ppa:xanmod/edge || { log "Ошибка при добавлении репозитория"; exit 1; }
            apt-get update || { log "Ошибка при обновлении пакетов"; exit 1; }
        fi
    else
        if [ ! -f "/etc/apt/trusted.gpg.d/xanmod-kernel.gpg" ]; then
            log "Добавление репозитория для Debian..."
            curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg || { log "Ошибка при добавлении ключа"; exit 1; }
            echo "deb http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod-kernel.list || { log "Ошибка при добавлении репозитория"; exit 1; }
            apt-get update || { log "Ошибка при обновлении пакетов"; exit 1; }
        fi
    fi

    # Установка
    KERNEL_PACKAGE="linux-xanmod-${PSABI_VERSION}"
    log "Установка пакета: $KERNEL_PACKAGE"
    apt-get install -y "$KERNEL_PACKAGE" || { log "Ошибка при установке ядра"; exit 1; }

    # Обновление GRUB
    log "Обновление конфигурации GRUB..."
    update-grub || { log "Ошибка при обновлении GRUB"; exit 1; }

    echo "kernel_installed" > "$STATE_FILE"
    log "Ядро успешно установлено. Требуется перезагрузка."
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
    
    # Проверяем, запущен ли скрипт с флагом --continue
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
                log "Продолжение после перезагрузки..."
                check_kernel || true  # Пропускаем ошибку проверки ядра
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

# Если скрипт запущен через pipe, сначала сохраняем его
if [ ! -t 0 ]; then
    cat > "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    exec "$TEMP_SCRIPT" "$@"
else
    main "$@"
fi