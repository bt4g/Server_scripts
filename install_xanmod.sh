#!/bin/bash

set -euo pipefail
exec > >(tee -a "/var/log/xanmod_install.log") 2>&1

# Константы
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-bbr.conf"

# Функция логирования
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Обработчик прерываний
cleanup() {
    log "Скрипт прерван. Очистка временных файлов..."
    rm -f "$STATE_FILE"
    exit 1
}
trap cleanup INT TERM EXIT

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Ошибка: Этот скрипт должен быть запущен с правами root."
        exit 1
    fi
}

# Проверка загруженного ядра
check_kernel() {
    local installed_kernel=$(ls /boot/vmlinuz-* 2>/dev/null | grep "xanmod" | sort -V | tail -n1 | awk -F'-' '{print $2"-"$3}')
    local current_kernel=$(uname -r)
    
    if [[ "$installed_kernel" != "" && "$installed_kernel" != "$current_kernel" ]]; then
        log "ВНИМАНИЕ: Система не загружена на ядре Xanmod. Текущее ядро: $current_kernel"
        exit 1
    fi
}

# Проверка интернет-соединения
check_internet() {
    if ! ping -c1 -W3 google.com &>/dev/null; then
        log "Ошибка: Нет подключения к интернету."
        exit 1
    fi
}

# Проверка свободного места
check_disk_space() {
    local required_space=2000  # 2GB в MB
    local available_space=$(df --output=avail -m / | awk 'NR==2 {print $1}')
    
    if (( available_space < required_space )); then
        log "Ошибка: Недостаточно свободного места (минимум 2 ГБ)."
        exit 1
    fi
}

# Проверка ОС
check_os() {
    if ! grep -E -q "Ubuntu|Debian" /etc/os-release; then
        log "Ошибка: Этот скрипт поддерживает только Ubuntu и Debian."
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
        log "Ошибка: Поддерживается только x86_64 архитектура."
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
    apt-get upgrade -y || { log "Ошибка при выполнении apt-get upgrade"; exit 1; }
    apt-get dist-upgrade -y || { log "Ошибка при выполнении apt-get dist-upgrade"; exit 1; }
    apt-get autoclean -y || { log "Ошибка при выполнении apt-get autoclean"; exit 1; }
    apt-get autoremove -y || { log "Ошибка при выполнении apt-get autoremove"; exit 1; }
    log "Обновление системы завершено успешно"
}

# Очистка системы
system_cleanup() {
    log "Начало очистки системы..."
    apt-get autoremove --purge -y || { log "Ошибка при выполнении apt-get autoremove --purge"; exit 1; }
    log "Очистка системы завершена успешно"
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
    log "Настройка BBR завершена успешно."
}

# Главная функция
main() {
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
                rm -f "$STATE_FILE"
                check_kernel
                install_kernel

                echo -e "\n\033[1;33m[ВНИМАНИЕ]\033[0m Требуется перезагрузка для активации ядра."
                read -p "Нажмите Enter для перезагрузки..."
                reboot
                ;;
            "kernel_installed")
                log "Завершающий этап: Настройка BBR"
                configure_bbr
                system_cleanup
                rm -f "$STATE_FILE"
                log "Установка успешно завершена!"
                ;;
        esac
    else
        log "Начало установки..."
        system_update
        echo "update_complete" > "$STATE_FILE"
        echo -e "\n\033[1;33m[ВНИМАНИЕ]\033[0m Требуется первая перезагрузка."
        read -p "Нажмите Enter для перезагрузки..."
        reboot
    fi
}

main