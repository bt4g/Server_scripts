#!/bin/bash

# Version: 1.0.0
# Author: gopnikgame
# Created: 2025-02-20 20:00:00
# Last Modified: 2025-02-20 20:00:00
# Description: Automatic VPS update management module

set -e

# Цветовые коды
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Константы
CRON_FILE="/etc/cron.d/auto_update_vps"
UPDATE_SCRIPT="/usr/local/sbin/auto_update_script.sh"
LOG_FILE="/var/log/auto_update_vps.log"
CONFIG_FILE="/etc/auto_update_vps.conf"
LOCK_FILE="/var/lock/auto_update_vps.lock"

# Функции для красивого вывода
print_header() {
    local title="$1"
    local width=50
    local padding=$(( (width - ${#title}) / 2 ))
    echo
    echo -e "${BLUE}?$( printf '?%.0s' $(seq 1 $width) )?${NC}"
    echo -e "${BLUE}?$( printf ' %.0s' $(seq 1 $padding) )${CYAN}$title$( printf ' %.0s' $(seq 1 $(( width - padding - ${#title} )) ) )${BLUE}?${NC}"
    echo -e "${BLUE}?$( printf '?%.0s' $(seq 1 $width) )?${NC}"
    echo
}

print_step() {
    echo -e "${YELLOW}?${NC} $1"
}

print_success() {
    echo -e "${GREEN}?${NC} $1"
}

print_error() {
    echo -e "${RED}?${NC} $1"
}

# Функция логирования
log() {
    local level="$1"
    shift
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    case "$level" in
        "INFO") local color=$GREEN ;;
   "WARNING") local color=$YELLOW ;;
        "ERROR") local color=$RED ;;
  *) local color=$NC ;;
    esac
    echo -e "${timestamp} [${color}${level}${NC}] $*"
    echo "${timestamp} [${level}] $*" >> "$LOG_FILE"
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка статуса автообновления
check_auto_update_status() {
    if [ -f "$CONFIG_FILE" ] && [ -f "$CRON_FILE" ]; then
        return 0  # Включено
    else
        return 1  # Отключено
    fi
}

# Получение настроек из конфига
get_config_value() {
    local key="$1"
    local default="$2"
    
    if [ -f "$CONFIG_FILE" ]; then
        local value=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2-)
        echo "${value:-$default}"
    else
      echo "$default"
    fi
}

# Показ текущих настроек
show_current_settings() {
    if ! check_auto_update_status; then
        echo -e "Статус: ${RED}Отключено${NC}"
        return 1
    fi
    
    local update_schedule=$(get_config_value "UPDATE_SCHEDULE" "неизвестно")
    local auto_reboot=$(get_config_value "AUTO_REBOOT" "no")
    local update_time=$(get_config_value "UPDATE_TIME" "03:00")
  local last_update=$(get_config_value "LAST_UPDATE" "никогда")
    
    echo -e "Статус:       ${GREEN}Включено${NC}"
    echo -e "График обновлений:    ${BLUE}$update_schedule${NC}"
  echo -e "Время обновления: ${BLUE}$update_time${NC}"
    echo -e "Автоперезагрузка:     $([ "$auto_reboot" = "yes" ] && echo -e "${GREEN}Включена${NC}" || echo -e "${YELLOW}Отключена${NC}")"
    
    if [ "$last_update" != "никогда" ]; then
 echo -e "Последнее обновление: ${CYAN}$last_update${NC}"
    else
        echo -e "Последнее обновление: ${YELLOW}$last_update${NC}"
    fi
    
    # Проверка наличия логов
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        echo -e "Размер лога:  ${CYAN}$log_size${NC}"
    fi
    
    return 0
}

# Создание скрипта обновления
create_update_script() {
    local auto_reboot="$1"
    
cat > "$UPDATE_SCRIPT" << 'EOF'
#!/bin/bash

# Автоматический скрипт обновления VPS
# Создан модулем auto_update_vps.sh

LOG_FILE="/var/log/auto_update_vps.log"
LOCK_FILE="/var/lock/auto_update_vps.lock"
CONFIG_FILE="/etc/auto_update_vps.conf"

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Проверка блокировки (предотвращение одновременного запуска)
if [ -f "$LOCK_FILE" ]; then
    log_message "INFO: Обновление уже выполняется, выход"
    exit 0
fi

# Создание файла блокировки
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

log_message "======================================"
log_message "INFO: Начало автоматического обновления"
log_message "======================================"

# Обновление списка пакетов
log_message "INFO: Обновление списка пакетов..."
if ! apt-get update >> "$LOG_FILE" 2>&1; then
    log_message "ERROR: Ошибка при обновлении списка пакетов"
    exit 1
fi
log_message "INFO: Список пакетов успешно обновлен"

# Проверка доступных обновлений
UPDATES_AVAILABLE=$(apt-get -s upgrade 2>/dev/null | grep -c "^Inst")
log_message "INFO: Доступно обновлений: $UPDATES_AVAILABLE"

if [ "$UPDATES_AVAILABLE" -eq 0 ]; then
    log_message "INFO: Нет доступных обновлений"
    
  # Обновляем дату последнего обновления
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/^LAST_UPDATE=.*/LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')/" "$CONFIG_FILE"
    fi
    
    exit 0
fi

# Установка переменных окружения для автоматических ответов
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# Настройка dpkg для сохранения существующих конфигов
cat > /etc/apt/apt.conf.d/99auto-update << 'APTCONF'
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
APT::Get::Assume-Yes "true";
APT::Get::force-yes "true";
APTCONF

# Выполнение обновления пакетов
log_message "INFO: Установка обновлений..."
if ! apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1; then
    log_message "ERROR: Ошибка при установке обновлений"
    exit 1
fi
log_message "INFO: Обновления успешно установлены"

# Выполнение dist-upgrade для системных пакетов
log_message "INFO: Выполнение dist-upgrade..."
if ! apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1; then
    log_message "WARNING: Возможны ошибки при dist-upgrade"
fi

# Автоочистка
log_message "INFO: Очистка ненужных пакетов..."
apt-get autoremove -y >> "$LOG_FILE" 2>&1
apt-get autoclean >> "$LOG_FILE" 2>&1
log_message "INFO: Очистка завершена"

# Обновление даты последнего обновления
if [ -f "$CONFIG_FILE" ]; then
    sed -i "s/^LAST_UPDATE=.*/LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')/" "$CONFIG_FILE"
fi

# Проверка необходимости перезагрузки
REBOOT_REQUIRED=false
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
    log_message "WARNING: Требуется перезагрузка системы"
fi

log_message "======================================"
log_message "INFO: Обновление завершено успешно"
log_message "======================================"

EOF

    # Добавление автоперезагрузки если включена
  if [ "$auto_reboot" = "yes" ]; then
        cat >> "$UPDATE_SCRIPT" << 'EOF'

# Автоматическая перезагрузка
AUTO_REBOOT=$(grep "^AUTO_REBOOT=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
if [ "$AUTO_REBOOT" = "yes" ] && [ "$REBOOT_REQUIRED" = true ]; then
    log_message "INFO: Выполняется автоматическая перезагрузка..."
    shutdown -r +2 "Автоматическая перезагрузка после обновления через 2 минуты" >> "$LOG_FILE" 2>&1
fi
EOF
    fi

    chmod +x "$UPDATE_SCRIPT"
    log "INFO" "Скрипт обновления создан: $UPDATE_SCRIPT"
}

# Настройка расписания cron
setup_cron_schedule() {
    local schedule_type="$1"
    local update_time="$2"
  
    # Разбиваем время на часы и минуты
    local hour=$(echo "$update_time" | cut -d':' -f1)
    local minute=$(echo "$update_time" | cut -d':' -f2)
    
 # Валидация времени
    if ! [[ "$hour" =~ ^[0-9]{1,2}$ ]] || [ "$hour" -gt 23 ] || [ "$hour" -lt 0 ]; then
        hour=3
    fi
    if ! [[ "$minute" =~ ^[0-9]{1,2}$ ]] || [ "$minute" -gt 59 ] || [ "$minute" -lt 0 ]; then
        minute=0
    fi
    
    local cron_schedule=""
    local schedule_description=""
    
    case "$schedule_type" in
     "weekly")
       # Каждое воскресенье в указанное время
      cron_schedule="$minute $hour * * 0"
     schedule_description="Еженедельно (каждое воскресенье)"
  ;;
   "biweekly")
            # Каждые две недели (1-е и 15-е число)
      cron_schedule="$minute $hour 1,15 * *"
      schedule_description="Раз в две недели (1-го и 15-го числа)"
            ;;
        "monthly")
   # Первое число каждого месяца
  cron_schedule="$minute $hour 1 * *"
     schedule_description="Ежемесячно (1-го числа)"
        ;;
        "daily")
            # Каждый день (для тестирования)
            cron_schedule="$minute $hour * * *"
            schedule_description="Ежедневно"
 ;;
        *)
            log "ERROR" "Неизвестный тип расписания: $schedule_type"
return 1
      ;;
    esac
    
    # Создание файла cron
    cat > "$CRON_FILE" << EOF
# Автоматическое обновление VPS
# Расписание: $schedule_description в ${hour}:$(printf "%02d" $minute)
# Создано: $(date '+%Y-%m-%d %H:%M:%S')

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$cron_schedule root $UPDATE_SCRIPT
EOF

    chmod 644 "$CRON_FILE"
    log "INFO" "Расписание cron настроено: $schedule_description в ${hour}:$(printf "%02d" $minute)"
    
    echo "$schedule_description"
}

# Включение автоматического обновления
enable_auto_update() {
    print_header "Настройка автоматического обновления"

    # Выбор графика обновлений
    echo -e "${YELLOW}=== Выбор графика обновлений ===${NC}"
    echo "1. Еженедельно (каждое воскресенье)"
    echo "2. Раз в две недели (1-го и 15-го числа)"
    echo "3. Ежемесячно (1-го числа каждого месяца)"
    echo "4. Ежедневно (для тестирования)"
    echo
    
    local schedule_type=""
    local schedule_name=""
    
    while true; do
   read -p "Выберите график обновлений [1-4, по умолчанию 1]: " choice
        choice="${choice:-1}"
        
        case "$choice" in
  1)
    schedule_type="weekly"
    schedule_name="Еженедельно"
  break
              ;;
        2)
         schedule_type="biweekly"
     schedule_name="Раз в две недели"
                break
          ;;
            3)
     schedule_type="monthly"
                schedule_name="Ежемесячно"
          break
       ;;
        4)
   schedule_type="daily"
     schedule_name="Ежедневно"
    echo -e "${YELLOW}? Внимание: Ежедневные обновления рекомендуются только для тестирования${NC}"
            break
 ;;
   *)
       print_error "Неверный выбор, попробуйте снова"
    ;;
        esac
    done
    
 log "INFO" "Выбран график обновлений: $schedule_name"
    
    # Выбор времени обновления
 echo
    echo -e "${YELLOW}=== Выбор времени обновления ===${NC}"
    echo "Рекомендуется выбирать ночное время с минимальной нагрузкой"
    echo "Формат: ЧЧ:ММ (например, 03:00 для 3 часов ночи)"
    echo
    
    local update_time="03:00"
    while true; do
 read -p "Введите время обновления [по умолчанию 03:00]: " input_time
        input_time="${input_time:-03:00}"
        
        # Проверка формата времени
        if [[ "$input_time" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            update_time="$input_time"
    break
 else
       print_error "Неверный формат времени. Используйте формат ЧЧ:ММ"
        fi
    done
    
    log "INFO" "Выбрано время обновления: $update_time"
    
    # Автоматическая перезагрузка
  echo
    echo -e "${YELLOW}=== Настройка автоматической перезагрузки ===${NC}"
    echo "После обновления некоторых системных компонентов может потребоваться перезагрузка."
    echo -e "${CYAN}Если включена автоперезагрузка, система будет автоматически перезагружена${NC}"
    echo -e "${CYAN}через 2 минуты после обновления (при необходимости).${NC}"
    echo
    
    local auto_reboot="no"
    read -p "Включить автоматическую перезагрузку после обновления? [y/N]: " reboot_choice
    
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
 auto_reboot="yes"
        log "INFO" "Автоматическая перезагрузка включена"
     echo -e "${GREEN}? Автоматическая перезагрузка включена${NC}"
    else
        log "INFO" "Автоматическая перезагрузка отключена"
        echo -e "${YELLOW}? Автоматическая перезагрузка отключена${NC}"
    fi
    
    # Создание конфигурационного файла
    print_step "Создание конфигурационного файла..."
    cat > "$CONFIG_FILE" << EOF
# Конфигурация автоматического обновления VPS
# Создано: $(date '+%Y-%m-%d %H:%M:%S')

UPDATE_SCHEDULE=$schedule_name
SCHEDULE_TYPE=$schedule_type
UPDATE_TIME=$update_time
AUTO_REBOOT=$auto_reboot
LAST_UPDATE=никогда
EOF

    # Создание скрипта обновления
    print_step "Создание скрипта обновления..."
    create_update_script "$auto_reboot"
    
    # Настройка расписания cron
    print_step "Настройка расписания обновлений..."
    local schedule_desc=$(setup_cron_schedule "$schedule_type" "$update_time")
    
    # Создание директории для логов
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "INFO" "Автоматическое обновление успешно настроено"
    print_success "Автоматическое обновление успешно настроено"
    
    # Вывод итоговой информации
    echo
    echo -e "${CYAN}??????????????????????????????????????????????????${NC}"
  echo -e "${CYAN}?${NC}     ${GREEN}Автоматическое обновление настроено${NC}     ${CYAN}?${NC}"
    echo -e "${CYAN}??????????????????????????????????????????????????${NC}"
    echo
  echo -e "${YELLOW}Параметры:${NC}"
  echo -e "  График:  ${BLUE}$schedule_name${NC}"
    echo -e "  Время:          ${BLUE}$update_time${NC}"
    echo -e "  Автоперезагрузка: $([ "$auto_reboot" = "yes" ] && echo -e "${GREEN}Включена${NC}" || echo -e "${YELLOW}Отключена${NC}")"
    echo
    echo -e "${YELLOW}Информация:${NC}"
    echo -e "  Файл конфигурации: ${CYAN}$CONFIG_FILE${NC}"
    echo -e "  Скрипт обновления: ${CYAN}$UPDATE_SCRIPT${NC}"
    echo -e "  Файл логов:        ${CYAN}$LOG_FILE${NC}"
    echo
    echo -e "${YELLOW}Примечания:${NC}"
    echo "  • При обновлении сохраняются существующие конфигурационные файлы"
    echo "  • Логи обновлений записываются в $LOG_FILE"
    echo "  • Для просмотра логов используйте: tail -f $LOG_FILE"
  
    if [ "$auto_reboot" = "yes" ]; then
      echo "  • Система будет автоматически перезагружена через 2 минуты после обновления (при необходимости)"
    fi
    echo
}

# Отключение автоматического обновления
disable_auto_update() {
    print_step "Отключение автоматического обновления..."
    
  local files_removed=0
    
    # Удаление cron задачи
    if [ -f "$CRON_FILE" ]; then
        rm -f "$CRON_FILE"
        log "INFO" "Удалена задача cron: $CRON_FILE"
    files_removed=$((files_removed + 1))
    fi
    
    # Удаление конфигурации
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
     log "INFO" "Удален конфигурационный файл: $CONFIG_FILE"
        files_removed=$((files_removed + 1))
    fi
    
    # Удаление скрипта обновления
    if [ -f "$UPDATE_SCRIPT" ]; then
        rm -f "$UPDATE_SCRIPT"
        log "INFO" "Удален скрипт обновления: $UPDATE_SCRIPT"
        files_removed=$((files_removed + 1))
 fi

    # Удаление конфигурации apt
    if [ -f /etc/apt/apt.conf.d/99auto-update ]; then
    rm -f /etc/apt/apt.conf.d/99auto-update
      log "INFO" "Удалена конфигурация apt"
        files_removed=$((files_removed + 1))
    fi
    
    if [ $files_removed -gt 0 ]; then
  log "INFO" "Автоматическое обновление отключено"
        print_success "Автоматическое обновление отключено"
        
 echo
        read -p "Удалить файл логов ($LOG_FILE)? [y/N]: " delete_logs
        if [[ "$delete_logs" =~ ^[Yy]$ ]]; then
     rm -f "$LOG_FILE"
   log "INFO" "Файл логов удален"
    print_success "Файл логов удален"
        else
            print_step "Файл логов сохранен для просмотра"
        fi
    else
        print_step "Автоматическое обновление не было настроено"
    fi
}

# Просмотр логов
view_logs() {
  print_header "Просмотр логов обновлений"

    if [ ! -f "$LOG_FILE" ]; then
        print_error "Файл логов не найден: $LOG_FILE"
        return 1
    fi
    
    local log_size=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
    local log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo -e "${CYAN}Информация о файле логов:${NC}"
    echo -e "  Путь:    ${BLUE}$LOG_FILE${NC}"
    echo -e "  Размер:  ${BLUE}$log_size${NC}"
    echo -e "  Строк:   ${BLUE}$log_lines${NC}"
    echo
    
    echo -e "${YELLOW}Выберите действие:${NC}"
  echo "1. Показать последние 50 строк"
echo "2. Показать последние 100 строк"
    echo "3. Показать весь лог"
  echo "4. Показать логи последнего обновления"
    echo "5. Отслеживать лог в реальном времени (tail -f)"
    echo "0. Назад"
    echo
    
 read -p "Выберите действие [0-5]: " choice
  
    case "$choice" in
        1)
    echo
       echo -e "${CYAN}=== Последние 50 строк ===${NC}"
     tail -n 50 "$LOG_FILE"
 ;;
        2)
     echo
echo -e "${CYAN}=== Последние 100 строк ===${NC}"
   tail -n 100 "$LOG_FILE"
      ;;
      3)
    echo
            echo -e "${CYAN}=== Весь лог ===${NC}"
            less "$LOG_FILE"
         ;;
        4)
            echo
   echo -e "${CYAN}=== Логи последнего обновления ===${NC}"
          # Ищем последний блок обновления
          tac "$LOG_FILE" | sed -n '/======================================/,/======================================/p' | tac
            ;;
        5)
   echo
    echo -e "${CYAN}=== Отслеживание лога (Ctrl+C для выхода) ===${NC}"
    tail -f "$LOG_FILE"
    ;;
        0)
     return 0
     ;;
        *)
   print_error "Неверный выбор"
     ;;
    esac
}

# Запуск обновления вручную
run_manual_update() {
    print_header "Запуск обновления вручную"
    
if [ ! -f "$UPDATE_SCRIPT" ]; then
  print_error "Скрипт обновления не найден. Сначала настройте автоматическое обновление."
        return 1
  fi
    
    echo -e "${YELLOW}? Внимание!${NC}"
    echo "Будет запущен процесс обновления системы."
 echo "Это может занять продолжительное время."
    echo
    
    read -p "Продолжить? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "INFO" "Ручное обновление отменено пользователем"
        print_step "Обновление отменено"
        return 0
    fi
    
    print_step "Запуск обновления..."
    log "INFO" "Запущено ручное обновление системы"
    
    # Запуск скрипта обновления
    if bash "$UPDATE_SCRIPT"; then
        print_success "Обновление завершено"
        
      # Показываем хвост лога
      echo
        echo -e "${CYAN}=== Последние строки лога ===${NC}"
        tail -n 20 "$LOG_FILE"
    else
        print_error "Ошибка при выполнении обновления"
        log "ERROR" "Ошибка при выполнении ручного обновления"
        
        # Показываем хвост лога с ошибками
  echo
   echo -e "${RED}=== Ошибки в логе ===${NC}"
        tail -n 30 "$LOG_FILE" | grep -i "error\|failed\|ошибка" || tail -n 30 "$LOG_FILE"
    fi
}

# Изменение настроек
modify_settings() {
    print_header "Изменение настроек"
    
    if ! check_auto_update_status; then
        print_error "Автоматическое обновление не настроено"
        return 1
    fi
    
    echo -e "${YELLOW}Текущие настройки:${NC}"
    echo "----------------------------------------"
    show_current_settings
    echo "----------------------------------------"
    echo
    
    echo -e "${YELLOW}Выберите параметр для изменения:${NC}"
    echo "1. Изменить график обновлений"
    echo "2. Изменить время обновления"
    echo "3. Изменить настройку автоперезагрузки"
    echo "0. Назад"
    echo
    
    read -p "Выберите действие [0-3]: " choice
    
    case "$choice" in
        1)
        # Читаем текущую конфигурацию
  local current_auto_reboot=$(get_config_value "AUTO_REBOOT" "no")
            local current_update_time=$(get_config_value "UPDATE_TIME" "03:00")
            
            # Повторяем процесс выбора графика
        echo
            echo -e "${YELLOW}=== Новый график обновлений ===${NC}"
         echo "1. Еженедельно (каждое воскресенье)"
        echo "2. Раз в две недели (1-го и 15-го числа)"
    echo "3. Ежемесячно (1-го числа каждого месяца)"
  echo "4. Ежедневно (для тестирования)"
 echo
            
            local new_schedule_type=""
   local new_schedule_name=""
            
            while true; do
   read -p "Выберите новый график [1-4]: " sched_choice
       
      case "$sched_choice" in
         1) new_schedule_type="weekly"; new_schedule_name="Еженедельно"; break ;;
        2) new_schedule_type="biweekly"; new_schedule_name="Раз в две недели"; break ;;
      3) new_schedule_type="monthly"; new_schedule_name="Ежемесячно"; break ;;
      4) new_schedule_type="daily"; new_schedule_name="Ежедневно"; break ;;
        *) print_error "Неверный выбор" ;;
    esac
            done
            
        # Обновляем конфигурацию
  sed -i "s/^UPDATE_SCHEDULE=.*/UPDATE_SCHEDULE=$new_schedule_name/" "$CONFIG_FILE"
       sed -i "s/^SCHEDULE_TYPE=.*/SCHEDULE_TYPE=$new_schedule_type/" "$CONFIG_FILE"
   
            # Пересоздаем cron
            setup_cron_schedule "$new_schedule_type" "$current_update_time" > /dev/null
     
            log "INFO" "График обновлений изменен на: $new_schedule_name"
            print_success "График обновлений изменен"
            ;;
     
        2)
      echo
  echo -e "${YELLOW}=== Новое время обновления ===${NC}"
   echo "Текущее время: $(get_config_value "UPDATE_TIME" "03:00")"
          echo
 
            local new_time=""
            while true; do
     read -p "Введите новое время (ЧЧ:ММ): " new_time
          
        if [[ "$new_time" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
         break
      else
    print_error "Неверный формат. Используйте ЧЧ:ММ"
  fi
            done

            # Обновляем конфигурацию
            sed -i "s/^UPDATE_TIME=.*/UPDATE_TIME=$new_time/" "$CONFIG_FILE"
         
         # Пересоздаем cron
       local current_schedule_type=$(get_config_value "SCHEDULE_TYPE" "weekly")
        setup_cron_schedule "$current_schedule_type" "$new_time" > /dev/null
            
   log "INFO" "Время обновления изменено на: $new_time"
            print_success "Время обновления изменено"
    ;;
    
      3)
         local current_reboot=$(get_config_value "AUTO_REBOOT" "no")
            local new_reboot=""
  
     echo
            echo -e "${YELLOW}=== Настройка автоперезагрузки ===${NC}"
            echo "Текущее значение: $([ "$current_reboot" = "yes" ] && echo "Включена" || echo "Отключена")"
   echo
    
       if [ "$current_reboot" = "yes" ]; then
         read -p "Отключить автоматическую перезагрузку? [y/N]: " disable
             if [[ "$disable" =~ ^[Yy]$ ]]; then
 new_reboot="no"
         else
     new_reboot="yes"
    fi
else
      read -p "Включить автоматическую перезагрузку? [y/N]: " enable
    if [[ "$enable" =~ ^[Yy]$ ]]; then
      new_reboot="yes"
 else
          new_reboot="no"
           fi
            fi
         
            # Обновляем конфигурацию
     sed -i "s/^AUTO_REBOOT=.*/AUTO_REBOOT=$new_reboot/" "$CONFIG_FILE"
      
    # Пересоздаем скрипт обновления
  create_update_script "$new_reboot"
            
log "INFO" "Автоперезагрузка $([ "$new_reboot" = "yes" ] && echo "включена" || echo "отключена")"
      print_success "Настройка автоперезагрузки обновлена"
          ;;
      
   0)
      return 0
            ;;
        
        *)
    print_error "Неверный выбор"
    ;;
    esac
}

# Главное меню
manage_auto_update() {
    check_root
    
    while true; do
        print_header "Автоматическое обновление VPS"
        
  echo -e "${CYAN}Текущее состояние:${NC}"
      echo "----------------------------------------"
        show_current_settings
      echo "----------------------------------------"
        echo
     
        echo -e "${YELLOW}Доступные действия:${NC}"
        
 if check_auto_update_status; then
      echo "1. Изменить настройки"
 echo "2. Просмотреть логи обновлений"
            echo "3. Запустить обновление вручную"
            echo "4. Отключить автоматическое обновление"
        else
            echo "1. Включить автоматическое обновление"
  fi
      
        echo "0. Вернуться в главное меню"
      echo
  
     read -p "Выберите действие: " choice
        echo
        
    if check_auto_update_status; then
      case $choice in
            0) return 0 ;;
            1) modify_settings ;;
       2) view_logs ;;
    3) run_manual_update ;;
        4) disable_auto_update ;;
     *) print_error "Неверный выбор" ;;
  esac
   else
   case $choice in
              0) return 0 ;;
                1) enable_auto_update ;;
    *) print_error "Неверный выбор" ;;
  esac
        fi
  
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

# Главная функция
main() {
    print_header "АВТООБНОВЛЕНИЕ VPS v1.0.0"
    manage_auto_update
}

# Запуск главной функции
main "$@"
