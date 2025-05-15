#!/bin/bash

# Функция для проверки существования команды
_exists() {
    command -v "$1" &>/dev/null
}

# Функции для цветного вывода
_red() {
    echo -e "\033[31m$1\033[0m"
}

_green() {
    echo -e "\033[32m$1\033[0m"
}

_yellow() {
    echo -e "\033[33m$1\033[0m"
}

# Тест DNS-серверов
run_dns_test() {
    echo
    echo " ⌛ Тестирование DNS-серверов..."
    
    # Массив DNS-серверов для проверки
    declare -A dns_servers
    dns_servers["Google"]="8.8.8.8"
    dns_servers["Cloudflare"]="1.1.1.1"
    dns_servers["AdGuard"]="94.140.14.14"
    dns_servers["Quad9"]="9.9.9.9"
    dns_servers["OpenDNS"]="208.67.222.222"
    dns_servers["CleanBrowsing"]="185.228.168.9"
    dns_servers["NextDNS"]="45.90.28.0"
    dns_servers["ControlD"]="76.76.2.0"
    dns_servers["Alternate DNS"]="76.76.19.19"
    dns_servers["UncensoredDNS"]="91.239.100.100"
    
    # Сайты для проверки DNS
    local test_domains=("google.com" "yandex.ru" "cloudflare.com")
    
    echo
    printf " %-18s %-20s %-10s\n" "DNS Сервер" "Провайдер" "Время (мс)"
    echo " -------------------------------------------------"
    
    # Определяем доступную утилиту для проверки DNS
    local dns_tool=""
    if _exists "dig"; then
        dns_tool="dig"
    elif _exists "nslookup"; then
        dns_tool="nslookup"
    else
        echo " $(_red "Ошибка: Не найдены утилиты dig или nslookup. Установите dnsutils или bind-utils.")"
        return
    fi
    
    for provider in "${!dns_servers[@]}"; do
        local server=${dns_servers[$provider]}
        local total_time=0
        local count=0
        
        for domain in "${test_domains[@]}"; do
            if [ "$dns_tool" = "dig" ]; then
                # Используем dig с увеличенным таймаутом
                local start_time=$(date +%s%N)
                local result=$(dig @$server $domain +short +time=2 +retry=1 2>/dev/null)
                local end_time=$(date +%s%N)
                
                if [ -n "$result" ]; then
                    # Расчет времени в миллисекундах (ms)
                    local query_time=$(( (end_time - start_time) / 1000000 ))
                    total_time=$((total_time + query_time))
                    count=$((count + 1))
                fi
            else
                # Используем nslookup с таймером
                local start_time=$(date +%s%N)
                local result=$(nslookup -timeout=2 $domain $server 2>/dev/null)
                local end_time=$(date +%s%N)
                
                # Проверяем, что запрос был успешным
                if echo "$result" | grep -q "Address:" && ! echo "$result" | grep -q "server can't find"; then
                    # Расчет времени в миллисекундах (ms)
                    local query_time=$(( (end_time - start_time) / 1000000 ))
                    total_time=$((total_time + query_time))
                    count=$((count + 1))
                fi
            fi
        done
        
        if [[ $count -gt 0 ]]; then
            local avg_time=$((total_time / count))
            
            # Цветовое отображение в зависимости от скорости
            if [[ $avg_time -lt 30 ]]; then
                printf " %-18s %-20s $(_green "%-10s")\n" "$server" "$provider" "${avg_time} мс"
            elif [[ $avg_time -lt 60 ]]; then
                printf " %-18s %-20s $(_yellow "%-10s")\n" "$server" "$provider" "${avg_time} мс"
            else
                printf " %-18s %-20s $(_red "%-10s")\n" "$server" "$provider" "${avg_time} мс"
            fi
        else
            printf " %-18s %-20s $(_red "%-10s")\n" "$server" "$provider" "ошибка"
        fi
    done
    echo
}

run_traceroute() {
    echo
    echo " ⌛ Проверка маршрута к популярным DNS-серверам..."
    
    # Проверяем наличие команды traceroute или tracepath
    if _exists "traceroute"; then
        local cmd="traceroute"
    elif _exists "tracepath"; then
        local cmd="tracepath"
    else
        echo " $(_red "Ошибка: traceroute/tracepath не установлен!")"
        return
    fi
    
    # Ассоциативный массив DNS-серверов (в bash 4.0+)
    declare -A dns_servers=(
        ["Google"]="8.8.8.8"
        ["Cloudflare"]="1.1.1.1"
        ["AdGuard"]="94.140.14.14"
        ["Quad9"]="9.9.9.9"
        ["OpenDNS"]="208.67.222.222"
        ["CleanBrowsing"]="185.228.168.9"
        ["NextDNS"]="45.90.28.0"
        ["ControlD"]="76.76.2.0"
        ["Alternate DNS"]="76.76.19.19"
        ["UncensoredDNS"]="91.239.100.100"
    )
    
    # Для совместимости с bash < 4.0 можно использовать два массива:
    # dns_names=("Google" "Cloudflare" ...)
    # dns_ips=("8.8.8.8" "1.1.1.1" ...)
    
    for dns_name in "${!dns_servers[@]}"; do
        local target=${dns_servers[$dns_name]}
        echo
        echo " $(_yellow "★") Маршрут к $dns_name DNS (${target}):"
        
        # Ограничиваем трассировку 10 хопами для ускорения
        if [[ "$cmd" == "traceroute" ]]; then
            $cmd -m 10 -w 2 $target 2>&1 | grep -v '* * *' | head -n 15
        else
            $cmd -m 10 $target 2>&1 | grep -v '(mtu' | grep -v 'no reply' | head -n 15
        fi
    done
    echo
}

# Генерация отчета
generate_report() {
    echo
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   ОТЧЁТ О ПРОВЕРКЕ DNS И СЕТИ                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo
    echo "$(_yellow "▶") Дата проверки: $(date '+%d.%m.%Y %H:%M:%S')"
    echo
    echo "$(_yellow "▶") Информация о системе:"
    echo "   Хост: $(hostname)"
    if _exists "lsb_release"; then
        echo "   ОС: $(lsb_release -ds 2>/dev/null)"
    elif [ -f "/etc/os-release" ]; then
        echo "   ОС: $(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '"')"
    fi
    echo
    echo "$(_yellow "▶") Текущие настройки DNS:"
    if [ -f "/etc/resolv.conf" ]; then
        grep nameserver /etc/resolv.conf | sed 's/nameserver/   Nameserver:/'
    fi
    
    echo
    echo "$(_yellow "▶") Результаты тестирования DNS:"
    echo "   $(_green "< 30 мс") - отличное время отклика"
    echo "   $(_yellow "30-60 мс") - хорошее время отклика"
    echo "   $(_red "> 60 мс") - медленное время отклика"
    
    # Запуск теста DNS
    run_dns_test
    
    # Запуск трассировки
    run_traceroute
    
    echo
    echo "$(_yellow "▶") РЕКОМЕНДАЦИИ:"
    echo "   1. DNS-серверы с временем отклика менее 30 мс обеспечат наилучшую производительность при веб-серфинге."
    echo "   2. При выборе DNS-сервера учитывайте не только скорость, но и приватность, фильтрацию контента."
    echo "   3. Для улучшения производительности можно настроить использование нескольких DNS-серверов."
    echo "   4. Трассировка показывает количество переходов до целевых серверов - меньшее количество обычно означает более быстрое соединение."
    echo
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                          КОНЕЦ ОТЧЁТА                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
}

# Главная функция
main() {
    # Проверка наличия необходимых утилит
    if ! _exists "dig" && ! _exists "nslookup"; then
        echo " $(_red "Ошибка: Необходима утилита dig или nslookup для проверки DNS. Установите dnsutils или bind-utils.")"
        exit 1
    fi
    
    if ! _exists "traceroute" && ! _exists "tracepath"; then
        echo " $(_red "Ошибка: Необходима утилита traceroute или tracepath. Установите traceroute или iputils.")"
        exit 1
    fi
    
    # Запуск отчета
    generate_report
}

# Запуск скрипта
main
