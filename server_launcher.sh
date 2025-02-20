#!/bin/bash

# Version: 1.0.2
# Author: gopnikgame
# Created: 2025-02-20 10:31:01
# Last Modified: 2025-02-20 17:23:53
# Current User: gopnikgame

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Константы
MODULES_DIR="/usr/local/server-scripts/modules"
LOG_DIR="/var/log/server-scripts"
GITHUB_RAW="https://raw.githubusercontent.com/gopnikgame/Server_scripts/main"
SCRIPT_VERSION="1.0.2"

# Массив модулей с версиями
declare -A MODULES=(
    ["ubuntu_pre_install.sh"]="Первоначальная настройка Ubuntu 24.04"
    ["install_xanmod.sh"]="Установка XanMod Kernel с BBR3"
    ["bbr_info.sh"]="Проверка и настройка конфигурации BBR"
)

# Функция логирования
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [$1] $2"
    echo -e "${timestamp} [$1] $2" >> "$LOG_DIR/server-scripts.log"
}

# Создание необходимых директорий
create_directories() {
    mkdir -p "$MODULES_DIR"
    mkdir -p "$LOG_DIR"
    chmod 755 "$MODULES_DIR"
    chmod 755 "$LOG_DIR"
}

# Проверка и загрузка модулей
check_and_download_modules() {
    local missing_modules=0
    local force_update=${1:-false}
    
    for module in "${!MODULES[@]}"; do
        if [ "$module" = "bbr_info.sh" ] || [ ! -f "$MODULES_DIR/$module" ] || [ "$force_update" = true ]; then
            log "INFO" "Загрузка/обновление модуля: $module..."
            if wget -q "$GITHUB_RAW/$module" -O "$MODULES_DIR/$module.tmp"; then
                mv "$MODULES_DIR/$module.tmp" "$MODULES_DIR/$module"
                chmod +x "$MODULES_DIR/$module"
                log "SUCCESS" "Модуль $module успешно обновлен"
            else
                rm -f "$MODULES_DIR/$module.tmp"
                log "ERROR" "Ошибка загрузки модуля $module"
                ((missing_modules++))
            fi
        fi
    done
    
    return $missing_modules
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "${RED}Этот скрипт должен быть запущен с правами root${NC}"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    local deps=("wget" "curl" "sysctl" "modinfo" "grep")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "INFO" "Установка необходимых зависимостей: ${missing_deps[*]}"
        if [ -f /etc/debian_version ]; then
            apt-get update -qq
            apt-get install -y "${missing_deps[@]}" procps
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}" procps-ng
        else
            log "ERROR" "Неподдерживаемый дистрибутив"
            exit 1
        fi
    fi
}

# Показать справку
show_help() {
    echo -e "${BLUE}=== Server Scripts Manager v${SCRIPT_VERSION} ===${NC}"
    echo -e "${YELLOW}Использование:${NC}"
    echo "curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- [опция]"
    echo
    echo "Опции:"
    echo "  -p, --preinstall Первоначальная настройка Ubuntu 24.04"
    echo "  -i, --install    Установка XanMod Kernel с BBR3"
    echo "  -c, --check      Проверка и настройка конфигурации BBR"
    echo "  -u, --update     Обновить все модули"
    echo "  -h, --help       Показать эту справку"
    echo
    echo "Примеры:"
    echo "  Первоначальная настройка Ubuntu:"
    echo "    curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -p"
    echo
    echo "  Установка XanMod:"
    echo "    curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -i"
    echo
    echo "  Проверка и настройка BBR:"
    echo "    curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -c"
}

# Запуск выбранного модуля
run_module() {
    local module_name=$1
    if [ -f "$MODULES_DIR/$module_name" ]; then
        log "INFO" "Запуск модуля: $module_name"
        bash "$MODULES_DIR/$module_name"
        return $?
    else
        log "ERROR" "Модуль $module_name не найден"
        return 1
    fi
}

# Основная функция
main() {
    # Проверки
    check_root
    check_dependencies
    create_directories
    
    # Обработка параметров
    case "$1" in
        -p|--preinstall)
            if ! check_and_download_modules; then
                log "ERROR" "${RED}Не удалось загрузить все необходимые модули${NC}"
                exit 1
            fi
            run_module "ubuntu_pre_install.sh"
            ;;
        -i|--install)
            if ! check_and_download_modules; then
                log "ERROR" "${RED}Не удалось загрузить все необходимые модули${NC}"
                exit 1
            fi
            run_module "install_xanmod.sh"
            ;;
        -c|--check)
            if ! check_and_download_modules; then
                log "ERROR" "${RED}Не удалось загрузить все необходимые модули${NC}"
                exit 1
            fi
            run_module "bbr_info.sh"
            ;;
        -u|--update)
            if ! check_and_download_modules true; then
                log "ERROR" "${RED}Не удалось обновить все модули${NC}"
                exit 1
            fi
            log "SUCCESS" "Все модули успешно обновлены"
            ;;
        -h|--help|"")
            show_help
            ;;
        *)
            log "ERROR" "Неизвестный параметр: $1"
            show_help
            exit 1
            ;;
    esac
}

# Запуск основной функции с переданными параметрами
main "$@"