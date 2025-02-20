#!/bin/bash

# Version: 1.0.4
# Author: gopnikgame
# Created: 2025-02-20 10:31:01
# Last Modified: 2025-02-20 18:01:39
# Current User: gopnikgame

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Константы
SCRIPT_DIR="/root/server-scripts"
MODULES_DIR="/usr/local/server-scripts/modules"
LOG_DIR="/var/log/server-scripts"
GITHUB_RAW="https://raw.githubusercontent.com/gopnikgame/Server_scripts/main"
SCRIPT_VERSION="1.0.4"
SCRIPT_NAME="server_launcher.sh"

# Массив модулей с версиями
declare -A MODULES=(
    ["ubuntu_pre_install.sh"]="Первоначальная настройка Ubuntu 24.04"
    ["install_xanmod.sh"]="Установка XanMod Kernel с BBR3"
    ["bbr_info.sh"]="Проверка и настройка конфигурации BBR"
)

# Функция рисования линий
draw_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '─'
}

# Функция центрирования текста
center_text() {
    local text="$1"
    local width="${COLUMNS:-$(tput cols)}"
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s%s%${padding}s\n" '' "$text" ''
}

# Функция вывода заголовка
print_header() {
    clear
    echo -e "${BLUE}"
    draw_line
    center_text "Server Scripts Manager v${SCRIPT_VERSION}"
    draw_line
    echo -e "${NC}"
}

# Функция вывода системной информации
print_system_info() {
    local kernel=$(uname -r)
    local os=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)
    local hostname=$(hostname)
    local uptime=$(uptime -p)
    local memory=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    local disk=$(df -h / | awk 'NR==2 {print $4 "/" $2}')
    local ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n1)
    
    echo -e "${CYAN}┌─ Системная информация ───────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}Хост:${NC}      $hostname"
    echo -e "${CYAN}│${NC} ${WHITE}ОС:${NC}        $os"
    echo -e "${CYAN}│${NC} ${WHITE}Ядро:${NC}      $kernel"
    echo -e "${CYAN}│${NC} ${WHITE}Аптайм:${NC}    $uptime"
    echo -e "${CYAN}│${NC} ${WHITE}Память:${NC}    $memory"
    echo -e "${CYAN}│${NC} ${WHITE}Диск:${NC}      $disk свободно"
    echo -e "${CYAN}│${NC} ${WHITE}IP:${NC}        $ip"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo
}

# Функция логирования
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [$1] $2"
    echo -e "${timestamp} [$1] $2" >> "$LOG_DIR/server-scripts.log"
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
    
    echo -e "\n${YELLOW}Проверка и загрузка модулей...${NC}"
    echo -e "${CYAN}┌─ Статус модулей ────────────────────────────────────────────┐${NC}"
    
    for module in "${!MODULES[@]}"; do
        if [ ! -f "$MODULES_DIR/$module" ] || [ "$force_update" = true ]; then
            echo -ne "${CYAN}│${NC} ${WHITE}${module}${NC} "
            printf '%*s' $((45 - ${#module})) ''
            if wget -q "$GITHUB_RAW/$module" -O "$MODULES_DIR/$module.tmp"; then
                mv "$MODULES_DIR/$module.tmp" "$MODULES_DIR/$module"
                chmod +x "$MODULES_DIR/$module"
                echo -e "${GREEN}[OK]${NC}"
            else
                rm -f "$MODULES_DIR/$module.tmp"
                echo -e "${RED}[ОШИБКА]${NC}"
                ((missing_modules++))
            fi
        fi
    done
    
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    return $missing_modules
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}╔════ ОШИБКА ══════════════════════════════════════════════════╗"
        echo -e "║ Этот скрипт должен быть запущен с правами root              ║"
        echo -e "╚════════════════════════════════════════════════════════════════╝${NC}"
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
        echo -e "${YELLOW}Установка необходимых зависимостей: ${missing_deps[*]}${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update -qq
            apt-get install -y "${missing_deps[@]}" procps
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}" procps-ng
        else
            echo -e "${RED}Неподдерживаемый дистрибутив${NC}"
            exit 1
        fi
    fi
}

# Функция самообновления
self_update() {
    echo -e "\n${YELLOW}Проверка обновлений...${NC}"
    
    echo -e "${CYAN}┌─ Статус обновления ─────────────────────────────────────────┐${NC}"
    if wget -q "$GITHUB_RAW/$SCRIPT_NAME" -O "/tmp/$SCRIPT_NAME.tmp"; then
        local new_version=$(grep "# Version:" "/tmp/$SCRIPT_NAME.tmp" | awk '{print $3}')
        if [ "$new_version" != "$SCRIPT_VERSION" ]; then
            echo -e "${CYAN}│${NC} ${GREEN}Доступна новая версия ($new_version)!${NC}"
            mv "/tmp/$SCRIPT_NAME.tmp" "$SCRIPT_DIR/$SCRIPT_NAME"
            chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
            echo -e "${CYAN}│${NC} ${GREEN}Скрипт успешно обновлен${NC}"
            echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
            exec "$SCRIPT_DIR/$SCRIPT_NAME"
        else
            echo -e "${CYAN}│${NC} ${GREEN}У вас установлена последняя версия${NC}"
            echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
            rm -f "/tmp/$SCRIPT_NAME.tmp"
        fi
    else
        echo -e "${