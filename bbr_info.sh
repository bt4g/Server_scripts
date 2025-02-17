#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
CURRENT_DATE="2025-02-15 16:56:41"
CURRENT_USER="gopnikgame"

# Функция логирования
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m - $1"
}

log_error() {
    echo -e "\033[1;31m[ОШИБКА] - $1\033[0m"
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

# Проверка и установка зависимостей
check_dependencies() {
    local dependencies=("sysctl" "modinfo" "ss" "awk" "column" "grep")
    local missing_deps=()

    log "Проверка зависимостей..."
    
    # Проверка sudo прав
    if [ "$EUID" -ne 0 ]; then
        log_error "Скрипт требует привилегий суперпользователя (sudo)"
        exit 1
    fi

    for dep in "${dependencies[@]}"; do
        if ! check_command "$dep"; then
            case "$dep" in
                "sysctl")
                    missing_deps+=("procps")
                    ;;
                "ss")
                    missing_deps+=("iproute2")
                    ;;
                "awk"|"grep")
                    missing_deps+=("gawk" "grep")
                    ;;
                "column")
                    missing_deps+=("util-linux")
                    ;;
                *)
                    missing_deps+=("$dep")
                    ;;
            esac
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "Установка отсутствующих зависимостей: ${missing_deps[*]}"
        for package in "${missing_deps[@]}"; do
            if ! install_package "$package"; then
                log_error "Не удалось установить пакет: $package"
                exit 1
            fi
        done
        log "Все зависимости установлены"
    else
        log "✓ Все необходимые зависимости уже установлены"
    fi
}

print_bbr_phase() {
    case "$1" in
        1) echo "STARTUP - начальная фаза разгона" ;;
        2) echo "DRAIN - дренаж очереди" ;;
        3) echo "PROBE_RTT - измерение минимального RTT" ;;
        4) echo "PROBE_BW_UP - увеличение пропускной способности" ;;
        5) echo "PROBE_BW_DOWN - уменьшение пропускной способности" ;;
        6) echo "PROBE_BW_CRUISE - круизный режим" ;;
        7) echo "PROBE_BW_REFILL - наполнение" ;;
        *) echo "Неизвестная фаза" ;;
    esac
}

# Проверка зависимостей перед запуском основного скрипта
check_dependencies

# Проверка загрузки модуля BBR
if ! lsmod | grep -q '^tcp_bbr'; then
    log "Загрузка модуля BBR..."
    modprobe tcp_bbr
    if [ $? -ne 0 ]; then
        log_error "Не удалось загрузить модуль tcp_bbr"
        exit 1
    fi
fi

log "Проверка конфигурации BBR..."

# Проверка текущего алгоритма
current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
log "Текущий алгоритм управления перегрузкой: $current_cc"

# Проверка версии модуля BBR
bbr_version=$(modinfo tcp_bbr | grep "^version:" | awk '{print $2}')
if [[ "$bbr_version" == "3" ]]; then
    log "✓ Используется BBRv3 (версия модуля: $bbr_version)"
else
    log_error "Неожиданная версия BBR: $bbr_version (ожидается 3)"
fi

# Проверка доступных алгоритмов
available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control)
log "Доступные алгоритмы: $available_cc"

# Проверка планировщика очереди
qdisc=$(sysctl -n net.core.default_qdisc)
log "Текущий планировщик очереди: $qdisc"
if [[ "$qdisc" == "fq_pie" ]]; then
    log "✓ Используется оптимальный планировщик очереди для BBR3 (fq_pie)"
else
    log_error "Неоптимальный планировщик очереди: $qdisc (рекомендуется fq_pie для BBR3)"
fi

# Вывод текущих сетевых настроек
echo -e "\n\033[1;33mТекущие сетевые настройки:\033[0m"
echo "----------------------------------------"
{
    echo "Размеры буферов:"
    sysctl -n net.core.rmem_max
    sysctl -n net.core.wmem_max
    sysctl -n net.core.rmem_default
    sysctl -n net.core.wmem_default
    echo "TCP настройки:"
    sysctl -n net.ipv4.tcp_rmem
    sysctl -n net.ipv4.tcp_wmem
    sysctl -n net.ipv4.tcp_fastopen
    sysctl -n net.ipv4.tcp_ecn
} | column -t

echo -e "\n\033[1;33mСтатистика BBR для активных соединений:\033[0m"
echo "----------------------------------------"
ss -iti | grep -i bbr | while read -r line; do
    phase=$(echo "$line" | awk '{print $8}')
    echo -e "Фаза BBR: $(print_bbr_phase "$phase")"
    echo "$line"
done

# Проверка ECN
ecn_status=$(sysctl -n net.ipv4.tcp_ecn)
log "Статус ECN: $([[ "$ecn_status" == "1" ]] && echo "включен" || echo "выключен")"

# Итоговая проверка
if [[ "$current_cc" == "bbr" && "$bbr_version" == "3" && "$qdisc" == "fq_pie" ]]; then
    log "✓ BBR3 активен и правильно настроен"
    
    echo -e "\n\033[1;32mСистема оптимально настроена для BBR3\033[0m"
else
    log_error "BBR3 настроен некорректно"
    
    echo -e "\n\033[1;33mРекомендации по исправлению:\033[0m"
    [[ "$current_cc" != "bbr" ]] && echo "- Установите 'net.ipv4.tcp_congestion_control=bbr'"
    [[ "$qdisc" != "fq_pie" ]] && echo "- Установите 'net.core.default_qdisc=fq_pie'"
    [[ "$ecn_status" != "1" ]] && echo "- Включите ECN: 'net.ipv4.tcp_ecn=1'"
fi