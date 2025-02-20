#!/bin/bash

# Version: 1.0.1
# Author: gopnikgame
# Last Modified: 2025-02-20 11:16:02
CURRENT_DATE="2025-02-20 11:16:02"
CURRENT_USER="gopnikgame"

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Конфигурационный файл
SYSCTL_CONFIG="/etc/sysctl.d/99-xanmod-bbr.conf"

# Функция логирования
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m - $1"
}

log_error() {
    echo -e "\033[1;31m[ОШИБКА] - $1\033[0m"
}

log_success() {
    echo -e "\033[1;32m[УСПЕХ] - $1\033[0m"
}

# Функция проверки наличия команды
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Команда '$1' не найдена"
        return 1
    fi
    return 0
}

# Функция установки пакетов
install_package() {
    local package=$1
    if [ -f /etc/debian_version ]; then
        apt-get install -y "$package"
    elif [ -f /etc/redhat-release ]; then
        yum install -y "$package"
    else
        log_error "Неподдерживаемый дистрибутив"
        return 1
    fi
}

# Функция проверки и загрузки модуля BBR
check_and_load_bbr() {
    if ! lsmod | grep -q "^tcp_bbr "; then
        log "Загрузка модуля tcp_bbr..."
        modprobe tcp_bbr
        if [ $? -ne 0 ]; then
            log_error "Ошибка загрузки модуля tcp_bbr"
            return 1
        fi
    fi
    return 0
}

# Функция применения оптимизированных настроек
apply_optimized_settings() {
    log "Применение оптимизированных настроек сети..."
    
    cat > "$SYSCTL_CONFIG" <<EOF
# BBR3 core settings
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr

# TCP optimizations for XanMod
net.ipv4.tcp_ecn=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_low_latency=1

# Buffer settings optimized for 10Gbit+ networks
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.core.optmem_max=65536
net.ipv4.tcp_rmem=4096 1048576 67108864
net.ipv4.tcp_wmem=4096 1048576 67108864

# BBR3 specific optimizations
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_notsent_lowat=131072
net.core.netdev_max_backlog=16384
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_max_tw_buckets=2000000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1

# Additional XanMod optimizations
net.core.busy_read=50
net.core.busy_poll=50
net.ipv4.tcp_max_orphans=16384
EOF

    # Применение настроек
    if ! sysctl -p "$SYSCTL_CONFIG"; then
        log_error "Ошибка применения настроек sysctl"
        return 1
    fi
    
    log_success "Сетевые настройки успешно применены"
    return 0
}

# Функция обновления параметров GRUB
update_grub_settings() {
    log "Обновление параметров загрузки GRUB..."
    
    # Создание резервной копии
    if [ ! -f /etc/default/grub.backup ]; then
        cp /etc/default/grub /etc/default/grub.backup
    fi
    
    # Добавление параметров BBR если они отсутствуют
    if ! grep -q "tcp_congestion_control=bbr" /etc/default/grub; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="tcp_congestion_control=bbr /' /etc/default/grub
        if ! update-grub; then
            log_error "Ошибка при обновлении GRUB"
            return 1
        fi
        log_success "Параметры GRUB обновлены"
    fi
    return 0
}

# Функция проверки и исправления конфигурации
check_and_fix_configuration() {
    local needs_fix=0
    local current_cc
    local current_qdisc
    local bbr_version
    
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    bbr_version=$(modinfo tcp_bbr 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "unknown")
    
    echo -e "\n${YELLOW}Проверка текущей конфигурации:${NC}"
    echo "----------------------------------------"
    echo -e "Алгоритм управления:    ${BLUE}$current_cc${NC}"
    echo -e "Планировщик очереди:    ${BLUE}$current_qdisc${NC}"
    echo -e "Версия BBR:             ${BLUE}$bbr_version${NC}"
    echo -e "ECN статус:             ${BLUE}$(sysctl -n net.ipv4.tcp_ecn)${NC}"
    echo "----------------------------------------"
    
    if [[ "$current_cc" != "bbr" || "$current_qdisc" != "fq_pie" ]]; then
        needs_fix=1
    fi
    
    if [[ "$bbr_version" != "3" ]]; then
        if ! uname -r | grep -q "xanmod"; then
            log_error "Ядро XanMod не установлено. Сначала установите ядро XanMod"
            return 1
        fi
    fi
    
    if [ $needs_fix -eq 1 ]; then
        echo -e "\n${YELLOW}Обнаружены проблемы в конфигурации. Хотите исправить? [y/N]${NC}"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if ! check_and_load_bbr; then
                return 1
            fi
            if ! apply_optimized_settings; then
                return 1
            fi
            if ! update_grub_settings; then
                return 1
            fi
            log_success "Конфигурация исправлена. Рекомендуется перезагрузить систему"
            echo -e "\n${YELLOW}Хотите перезагрузить систему сейчас? [y/N]${NC}"
            read -r reboot_answer
            if [[ "$reboot_answer" =~ ^[Yy]$ ]]; then
                reboot
            fi
        fi
    else
        log_success "Конфигурация BBR3 в порядке"
    fi
    
    return 0
}

# Главная функция
main() {
    # Проверка root прав
    if [ "$EUID" -ne 0 ]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
    
    echo -e "${BLUE}=== Проверка и настройка BBR3 ===${NC}"
    echo -e "Версия: 1.0.1"
    echo -e "Дата запуска: $CURRENT_DATE"
    echo -e "Пользователь: $CURRENT_USER\n"
    
    check_and_fix_configuration
    
    exit $?
}

# Запуск скрипта
main "$@"
