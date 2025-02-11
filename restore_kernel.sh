#!/bin/bash

# Скрипт для восстановления ядра из резервной копии

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Директория с резервными копиями
BACKUP_DIR="/var/backups"

# Функция для восстановления ядра
restore_kernel() {
    # Поиск последней резервной копии
    latest_backup=$(ls -t ${BACKUP_DIR}/kernel_* | head -n1)
    
    if [[ -z "$latest_backup" ]]; then
        echo "Резервная копия не найдена в ${BACKUP_DIR}"
        exit 1
    fi

    echo "Найдена резервная копия: $latest_backup"
    echo "Начинаем восстановление..."

    # Восстановление файлов ядра
    cp -r "${latest_backup}"/* /boot/

    # Обновление GRUB
    update-grub

    echo "Восстановление завершено. Пожалуйста, перезагрузите систему."
}

# Показать список доступных бэкапов
show_backups() {
    echo "Доступные резервные копии:"
    ls -lh ${BACKUP_DIR}/kernel_*
}

# Главное меню
echo "Восстановление ядра Linux"
echo "------------------------"
echo "1. Показать доступные резервные копии"
echo "2. Восстановить последнюю резервную копию"
echo "3. Выход"

read -p "Выберите действие (1-3): " choice

case $choice in
    1)
        show_backups
        ;;
    2)
        restore_kernel
        ;;
    3)
        exit 0
        ;;
    *)
        echo "Неверный выбор"
        exit 1
        ;;
esac
