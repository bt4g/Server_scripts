#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-20 10:20:40

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

# Массив модулей
declare -A MODULES=(
    ["install_xanmod.sh"]="Установка XanMod Kernel с BBR3"
    ["bbr_info.sh"]="Проверка конфигурации BBR"
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
    
    for module in "${!MODULES[@]}"; do
        if [ ! -f "$MODULES_DIR/$module" ]; then
            log "INFO" "Загрузка модуля: $module..."
            if wget -q "$GITHUB_RAW/$module" -O "$MODULES_DIR/$module"; then
                chmod +x "$MODULES_DIR/$module"
                log "SUCCESS" "Модуль $module успешно загружен"
            else
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
    local deps=("wget" "curl")
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
            apt-get install -y "${missing_deps[@]}"
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}"
        else
            log "ERROR" "Неподдерживаемый дистрибутив"
            exit 1
        fi
    fi
}

# Очистка экрана и вывод меню
show_menu() {
    clear
    echo -e "${BLUE}=== Server Scripts Manager ===${NC}"
    echo -e "${YELLOW}Текущая дата: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo

    local i=1
    for module in "${!MODULES[@]}"; do
        echo -e "$i. ${MODULES[$module]}"
        ((i++))
    done
    
    echo -e "\n0. Выход"
    echo
}

# Основная функция
main() {
    # Проверки
    check_root
    check_dependencies
    create_directories
    
    # Проверка и загрузка модулей
    if ! check_and_download_modules; then
        log "ERROR" "${RED}Не удалось загрузить все необходимые модули${NC}"
        exit 1
    fi

    # Если скрипт запущен через pipe, автоматически запускаем установку XanMod
    if [ ! -t 0 ]; then
        log "INFO" "Автоматический запуск установки XanMod"
        if [ -f "$MODULES_DIR/install_xanmod.sh" ]; then
            bash "$MODULES_DIR/install_xanmod.sh"
        else
            log "ERROR" "Модуль установки XanMod не найден"
            exit 1
        fi
        exit 0
    fi

    # Интерактивное меню для обычного запуска
    while true; do
        show_menu
        read -p "Выберите действие (0-${#MODULES[@]}): " choice
        
        case $choice in
            0)
                echo -e "\n${GREEN}До свидания!${NC}"
                exit 0
                ;;
            [1-9])
                local i=1
                for module in "${!MODULES[@]}"; do
                    if [ "$i" -eq "$choice" ]; then
                        if [ -f "$MODULES_DIR/$module" ]; then
                            bash "$MODULES_DIR/$module"
                        else
                            log "ERROR" "Модуль $module не найден"
                        fi
                        break
                    fi
                    ((i++))
                done
                ;;
            *)
                log "ERROR" "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# Запуск основной функции
main