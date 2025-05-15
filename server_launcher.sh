#!/bin/bash

# Version: 1.0.3
# Author: gopnikgame
# Created: 2025-02-20 18:16:21
# Last Modified: 2025-02-20 18:16:21
# Current User: gopnikgame

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Константы
SCRIPT_DIR="/root/server-scripts"
MODULES_DIR="/usr/local/server-scripts/modules"
LOG_DIR="/var/log/server-scripts"
GITHUB_RAW="https://raw.githubusercontent.com/gopnikgame/Server_scripts/main"
SCRIPT_VERSION="1.0.4"
SCRIPT_NAME="server_launcher.sh"

# Определяем порядок модулей с помощью индексированного массива
declare -a MODULE_ORDER=(
    "ubuntu_pre_install.sh"
    "install_xanmod.sh"
    "bbr_info.sh"
    "speed_dns.sh"
)

# Ассоциативный массив с описаниями (как было раньше)
declare -A MODULES=(
    ["ubuntu_pre_install.sh"]="Первоначальная настройка Ubuntu 24.04"
    ["install_xanmod.sh"]="Установка XanMod Kernel с BBR3"
    ["bbr_info.sh"]="Проверка и настройка конфигурации BBR"
    ["speed_dns.sh"]="Проверка DNS"
)

# Функции для красивого вывода
print_header() {
    local title="$1"
    local width=50
    local padding=$(( (width - ${#title}) / 2 ))
    echo
    echo -e "${BLUE}┌$( printf '─%.0s' $(seq 1 $width) )┐${NC}"
    echo -e "${BLUE}│$( printf ' %.0s' $(seq 1 $padding) )${CYAN}$title$( printf ' %.0s' $(seq 1 $(( width - padding - ${#title} )) ) )${BLUE}│${NC}"
    echo -e "${BLUE}└$( printf '─%.0s' $(seq 1 $width) )┘${NC}"
    echo
}

print_step() {
    echo -e "${YELLOW}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✔${NC} $1"
}

print_error() {
    echo -e "${RED}✘${NC} $1"
}

# Функция логирования
log() {
    local level="$1"
    shift
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [$level] $*" >> "$LOG_DIR/server-scripts.log"
}

# Создание необходимых директорий
create_directories() {
    mkdir -p "$SCRIPT_DIR"
    mkdir -p "$MODULES_DIR"
    mkdir -p "$LOG_DIR"
    chmod 755 "$SCRIPT_DIR"
    chmod 755 "$MODULES_DIR"
    chmod 755 "$LOG_DIR"
}

# Проверка и загрузка модулей
check_and_download_modules() {
    local missing_modules=0
    local force_update=${1:-false}
    
    print_header "ПРОВЕРКА МОДУЛЕЙ"
    for module in "${!MODULES[@]}"; do
        print_step "Проверка модуля ${module}..."
        if [ ! -f "$MODULES_DIR/$module" ] || [ "$force_update" = true ]; then
            if wget -q "$GITHUB_RAW/$module" -O "$MODULES_DIR/$module.tmp"; then
                mv "$MODULES_DIR/$module.tmp" "$MODULES_DIR/$module"
                chmod +x "$MODULES_DIR/$module"
                print_success "Модуль $module обновлен"
            else
                rm -f "$MODULES_DIR/$module.tmp"
                print_error "Ошибка загрузки модуля $module"
                ((missing_modules++))
            fi
        else
            print_success "Модуль $module уже установлен"
        fi
    done
    
    return $missing_modules
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    local deps=("wget" "curl" "sysctl" "modinfo" "grep")
    local missing_deps=()

    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ"
    for dep in "${deps[@]}"; do
        print_step "Проверка $dep..."
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
            print_error "$dep не найден"
        else
            print_success "$dep найден"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_step "Установка отсутствующих зависимостей: ${missing_deps[*]}"
        if [ -f /etc/debian_version ]; then
            apt-get update -qq
            apt-get install -y "${missing_deps[@]}" procps
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}" procps-ng
        else
            print_error "Неподдерживаемый дистрибутив"
            exit 1
        fi
    fi
}

# Функция самообновления
self_update() {
    print_header "ОБНОВЛЕНИЕ LAUNCHER"
    print_step "Проверка обновлений..."
    
    if wget -q "$GITHUB_RAW/$SCRIPT_NAME" -O "/tmp/$SCRIPT_NAME.tmp"; then
        local new_version=$(grep "# Version:" "/tmp/$SCRIPT_NAME.tmp" | awk '{print $3}')
        if [ "$new_version" != "$SCRIPT_VERSION" ]; then
            print_success "Доступна новая версия ($new_version)!"
            mv "/tmp/$SCRIPT_NAME.tmp" "$SCRIPT_DIR/$SCRIPT_NAME"
            chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
            print_success "Скрипт обновлен до версии $new_version"
            exec "$SCRIPT_DIR/$SCRIPT_NAME"
        else
            print_success "У вас установлена последняя версия"
            rm -f "/tmp/$SCRIPT_NAME.tmp"
        fi
    else
        print_error "Ошибка проверки обновлений"
    fi
}

# Показать главное меню
show_main_menu() {
    while true; do
        print_header "SERVER SCRIPTS MANAGER v${SCRIPT_VERSION}"
        echo -e "${YELLOW}Выберите действие:${NC}"
        echo
        
        local i=1
        
        # Выводим модули в заданном порядке
        for module in "${MODULE_ORDER[@]}"; do
            echo -e "$i) ${GREEN}${MODULES[$module]}${NC}"
            ((i++))
        done
        
        # Системные опции (остаются в конце)
        echo -e "$i) ${YELLOW}Обновить все модули${NC}"
        ((i++))
        echo -e "$i) ${YELLOW}Обновить launcher${NC}"
        ((i++))
        echo -e "0) ${RED}Выход${NC}"
        echo
        
        read -p "Выберите опцию [0-$((i-1))]: " choice
        echo

        case $choice in
            0)
                print_success "До свидания!"
                exit 0
                ;;
            $((i-1)))
                self_update
                ;;
            $((i-2)))
                check_and_download_modules true
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -lt $((i-2)) ]; then
                    run_module "${MODULE_ORDER[$((choice-1))]}"
                else
                    print_error "Неверный выбор"
                fi
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

# Запуск выбранного модуля
run_module() {
    local module_name=$1
    if [ -f "$MODULES_DIR/$module_name" ]; then
        print_header "ЗАПУСК МОДУЛЯ: $module_name"
        bash "$MODULES_DIR/$module_name"
        return $?
    else
        print_error "Модуль $module_name не найден"
        return 1
    fi
}

# Установка скрипта
install_script() {
    print_header "ПЕРВОНАЧАЛЬНАЯ УСТАНОВКА"
    create_directories
    
    if [ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
        cp "$0" "$SCRIPT_DIR/$SCRIPT_NAME"
        chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
    fi
    
    if [ ! -L "/usr/local/bin/$SCRIPT_NAME" ]; then
        ln -s "$SCRIPT_DIR/$SCRIPT_NAME" "/usr/local/bin/$SCRIPT_NAME"
    fi
    
    check_and_download_modules
}

# Основная функция
main() {
    check_root
    check_dependencies
    
    if [ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
        print_step "Первый запуск - установка скрипта..."
        install_script
    fi
    
    show_main_menu
}

# Запуск основной функции
main "$@"