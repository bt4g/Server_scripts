#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-20 10:09:53
# Description: Launcher for Server Scripts Collection

# Константы
REPO_URL="https://raw.githubusercontent.com/gopnikgame/Server_scripts/main"
CURRENT_DATE="2025-02-20 10:09:53"
CURRENT_USER="gopnikgame"
TEMP_DIR="/tmp/server_scripts"
VERSION="1.0.0"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} - $1"
}

# Функция вывода ошибок
log_error() {
    echo -e "${RED}[ОШИБКА] - $1${NC}"
}

# Функция проверки root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Функция проверки зависимостей
check_dependencies() {
    local deps=("curl" "wget")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Установка необходимых зависимостей..."
        if [ -f /etc/debian_version ]; then
            apt-get update -qq
            apt-get install -y "${missing_deps[@]}"
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}"
        else
            log_error "Неподдерживаемый дистрибутив"
            exit 1
        fi
    fi
}

# Функция очистки
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        log "Очистка временных файлов..."
        rm -rf "$TEMP_DIR"
    fi
}

# Функция загрузки скрипта
download_script() {
    local script_name=$1
    local target_dir=$2
    
    mkdir -p "$target_dir"
    
    log "Загрузка скрипта $script_name..."
    if ! curl -sSL "$REPO_URL/$script_name" -o "$target_dir/$script_name"; then
        log_error "Ошибка при загрузке скрипта $script_name"
        cleanup
        exit 1
    fi
    
    chmod +x "$target_dir/$script_name"
    log "✓ Скрипт $script_name успешно загружен"
}

# Функция показа меню и получения выбора
get_user_choice() {
    local choice
    
    # Сохраняем текущие настройки термина
    local saved_settings
    saved_settings=$(stty -g)
    
    # Настраиваем терминал для корректного чтения ввода
    stty raw -echo
    
    clear
    echo -e "${YELLOW}=== Server Scripts Launcher v${VERSION} ===${NC}"
    echo -e "Текущая дата: ${GREEN}$CURRENT_DATE${NC}"
    echo -e "Пользователь: ${GREEN}$CURRENT_USER${NC}\n"
    
    echo -e "${YELLOW}Доступные скрипты:${NC}"
    echo "1. Установка XanMod Kernel с BBR3 (install_xanmod.sh)"
    echo "2. Проверка конфигурации BBR (bbr_info.sh)"
    echo "3. Выход"
    echo
    echo -e "${YELLOW}Выберите действие (1-3):${NC}"
    
    # Читаем один символ
    choice=$(dd bs=1 count=1 2>/dev/null)
    
    # Восстанавливаем настройки термина
    stty "$saved_settings"
    
    # Печатаем выбор и переход на новую строку
    echo "$choice"
    echo
    
    case $choice in
        1|2|3) echo "$choice" ;;
        *) echo "invalid" ;;
    esac
}

# Функция запуска скрипта
run_script() {
    local script_path=$1
    log "Запуск скрипта..."
    
    if [ -x "$script_path" ]; then
        "$script_path"
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log "✓ Скрипт успешно выполнен"
        else
            log_error "Скрипт завершился с ошибкой (код: $exit_code)"
        fi
    else
        log_error "Скрипт не найден или не является исполняемым"
        return 1
    fi
}

# Основная функция
main() {
    # Проверка root прав
    check_root
    
    # Проверка и установка зависимостей
    check_dependencies
    
    # Создание временной директории
    mkdir -p "$TEMP_DIR"
    
    # Получаем выбор пользователя
    local choice
    choice=$(get_user_choice)
    
    case $choice in
        1)
            download_script "install_xanmod.sh" "$TEMP_DIR"
            run_script "$TEMP_DIR/install_xanmod.sh"
            ;;
        2)
            download_script "bbr_info.sh" "$TEMP_DIR"
            run_script "$TEMP_DIR/bbr_info.sh"
            ;;
        3)
            log "Выход из программы"
            ;;
        *)
            log_error "Неверный выбор. Пожалуйста, запустите скрипт заново."
            exit 1
            ;;
    esac
    
    # Очистка после выполнения
    cleanup
}

# Обработка прерывания
trap cleanup EXIT

# Запуск основной функции
main
