#!/bin/bash

set -euo pipefail

# Константы
readonly STATE_FILE="/var/tmp/xanmod_install_state"
readonly LOG_FILE="/var/log/xanmod_install.log"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-bbr.conf"

# Функция логирования
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Ошибка: Этот скрипт должен быть запущен с правами root."
        exit 1
    fi
}

# Проверка операционной системы
check_os() {
    if ! grep -E -q "Ubuntu|Debian" /etc/os-release; then
        log "Ошибка: Этот скрипт поддерживает только Ubuntu и Debian."
        exit 1
    fi
    # Определение дистрибутива
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

# Проверка и установка зависимостей
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

# Функция для обновления системы
system_update() {
    log "Начало обновления системы..."
    apt-get update || { log "Ошибка при выполнении apt-get update"; exit 1; }
    apt-get upgrade -y || { log "Ошибка при выполнении apt-get upgrade"; exit 1; }
    apt-get dist-upgrade -y || { log "Ошибка при выполнении apt-get dist-upgrade"; exit 1; }
    apt-get autoclean -y || { log "Ошибка при выполнении apt-get autoclean"; exit 1; }
    apt-get autoremove -y || { log "Ошибка при выполнении apt-get autoremove"; exit 1; }
    log "Обновление системы завершено успешно"
}

# Функция для очистки системы
system_cleanup() {
    log "Начало очистки системы..."
    apt-get autoremove --purge -y || { log "Ошибка при выполнении apt-get autoremove --purge"; exit 1; }
    log "Очистка системы завершена успешно"
}

# Функция определения PSABI версии
get_psabi_version() {
    local level=1
    local flags=$(grep -m1 flags /proc/cpuinfo | cut -d ':' -f 2)
    if [[ $flags =~ avx512 ]]; then level=4
    elif [[ $flags =~ avx2 ]]; then level=3
    elif [[ $flags =~ sse4_2 ]]; then level=2
    fi
    echo "x64v$level"
}

# Функция установки ядра
install_kernel() {
    log "Начало установки ядра Xanmod..."

    # Определение PSABI версии
    PSABI_VERSION=$(get_psabi_version)
    log "Определена PSABI версия: $PSABI_VERSION"

    # Добавление репозитория Xanmod
    if [[ "$DISTRO" == "ubuntu" ]]; then
        if ! grep -q "^deb .*/xanmod/kernel" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
            log "Добавление PPA репозитория Xanmod для Ubuntu..."
            add-apt-repository -y ppa:xanmod/edge || { log "Ошибка при добавлении репозитория."; exit 1; }
            apt-get update || { log "Ошибка при обновлении списка пакетов"; exit 1; }
        fi
    else
        if [ ! -f "/etc/apt/trusted.gpg.d/xanmod-kernel.gpg" ]; then
            log "Добавление репозитория Xanmod для Debian..."
            curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg || { log "Ошибка при добавлении ключа"; exit 1; }
            echo "deb http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod-kernel.list || { log "Ошибка при добавлении репозитория"; exit 1; }
            apt-get update || { log "Ошибка при обновлении списка пакетов"; exit 1; }
        fi
    fi

    # Установка ядра
    KERNEL_PACKAGE="linux-xanmod-${PSABI_VERSION}"
    log "Установка ядра $KERNEL_PACKAGE..."
    apt-get install -y "$KERNEL_PACKAGE" || { log "Ошибка при установке ядра."; exit 1; }

    # Обновление GRUB
    log "Обновление GRUB..."
    update-grub || { log "Ошибка при обновлении GRUB."; exit 1; }

    log "Ядро Xanmod установлено успешно."
    echo "kernel_installed" > "$STATE_FILE"
}

# Функция настройки TCP BBR
configure_bbr() {
    log "Начало настройки TCP BBR..."

    cat <<EOF > "$SYSCTL_CONFIG"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    sysctl --system || { log "Ошибка при применении настроек sysctl."; exit 1; }

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        log "TCP BBR успешно включен."
    else
        log "Ошибка: TCP BBR не включен."
        exit 1
    fi

    log "Настройка TCP BBR завершена успешно."
}

# Главная функция
main() {
    check_root
    check_os
    check_architecture
    check_dependencies

    # Проверка состояния установки
    if [[ -f "$STATE_FILE" ]]; then
        case $(cat "$STATE_FILE") in
            "update_complete")
                log "Продолжение установки после обновления системы..."
                rm -f "$STATE_FILE"
                install_kernel

                echo -e "\n\033[1;33mВНИМАНИЕ!\033[0m"
                echo "Ядро Xanmod успешно установлено. Требуется перезагрузка."
                echo "После перезагрузки, пожалуйста, запустите скрипт снова для настройки BBR."

                read -p "Нажмите Enter для перезагрузки системы..."
                reboot
                ;;
            "kernel_installed")
                log "Начало настройки TCP BBR..."
                configure_bbr

                # Очистка системы
                system_cleanup

                log "Установка и настройка успешно завершены!"
                rm -f "$STATE_FILE"
                exit 0
                ;;
        esac
    else
        # Начало процесса установки
        log "Начало обновления системы перед установкой ядра..."
        system_update

        log "Система обновлена. Требуется перезагрузка перед продолжением установки."
        echo "update_complete" > "$STATE_FILE"

        echo -e "\n\033[1;33mВНИМАНИЕ!\033[0m"
        echo "Система была обновлена и требует перезагрузки."
        echo "После перезагрузки, пожалуйста, запустите скрипт снова для продолжения установки."

        read -p "Нажмите Enter для перезагрузки системы..."
        reboot
    fi
}

# Запуск главной функции
main