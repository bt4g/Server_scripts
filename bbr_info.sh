#!/bin/bash

check_bbr_version() {
    log "Проверка версии BBR..."
    
    # Проверяем текущий алгоритм управления перегрузкой
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    log "Текущий алгоритм управления перегрузкой: $current_cc"

    # Проверяем доступные алгоритмы
    local available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control)
    log "Доступные алгоритмы: $available_cc"

    # Определяем версию BBR
    if [[ "$current_cc" == "bbr" ]]; then
        if sysctl net.ipv4.tcp_bbr2_parameters &>/dev/null; then
            log "Используется BBRv2"
            sysctl net.ipv4.tcp_bbr2_parameters
        elif sysctl net.ipv4.tcp_bbr3_congestion_control &>/dev/null; then
            log "Используется BBRv3"
            sysctl net.ipv4.tcp_bbr3_congestion_control
        else
            log "Используется BBRv1"
        fi

        # Проверяем параметры очереди
        local qdisc=$(sysctl -n net.core.default_qdisc)
        log "Текущий планировщик очереди: $qdisc"

        # Проверяем активность BBR
        if grep -q "bbr" /proc/sys/net/ipv4/tcp_congestion_control; then
            log "BBR активен и работает"
        else
            log "BBR установлен, но не активен"
        fi
    else
        log "BBR не используется. Текущий алгоритм: $current_cc"
    fi
}

# Для использования функции:
check_bbr_version
