# Автоматическая установка ядра XanMod с оптимизацией BBR3

![Version](https://img.shields.io/badge/version-1.0.1-blue)
![Last Updated](https://img.shields.io/badge/last%20updated-2025--02--20-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 📋 Описание

Коллекция скриптов для автоматизации установки и настройки серверного программного обеспечения, включая оптимизацию сетевого стека с использованием XanMod kernel и BBR3.

**Последнее обновление:** 2025-02-20 11:29:09 UTC  
**Автор:** gopnikgame

## 🚀 Возможности

- Автоматическая установка ядра XanMod с оптимизацией BBR3
- Проверка и настройка конфигурации BBR
- Оптимизация сетевого стека для высокопроизводительных серверов
- Автоматическое восстановление и исправление конфигурации
- Поддержка различных версий ядра XanMod (стабильная, edge, RT, LTS)

## 📦 Установка

### Быстрый старт

```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- [опция]
```

### Доступные опции

- `-i, --install` - Установка XanMod Kernel с BBR3
- `-c, --check` - Проверка и настройка конфигурации BBR
- `-u, --update` - Обновление всех модулей
- `-h, --help` - Показать справку

### Примеры использования

1. Установка XanMod kernel:
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -i
```

2. Проверка и настройка BBR:
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -c
```

3. Обновление всех модулей:
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -u
```

## 🛠 Компоненты

### server_launcher.sh (v1.0.1)
- Центральный скрипт управления
- Автоматическая загрузка и обновление модулей
- Проверка зависимостей и системных требований

### install_xanmod.sh (v1.0.0)
- Установка ядра XanMod
- Автоматический выбор оптимальной версии
- Настройка параметров загрузки
- Оптимизация системных параметров

### bbr_info.sh (v1.0.1)
- Проверка конфигурации BBR
- Автоматическое исправление проблем
- Мониторинг производительности
- Восстановление оптимальных настроек

## ⚙️ Системные требования

- OS: Debian/Ubuntu (x86_64)
- Права: root
- Минимальное свободное место: 2GB
- Зависимости: wget, curl, sysctl, modinfo

## 🔧 Оптимизации

### Сетевые настройки

- Оптимизированные буферы для сетей 10Gbit+
- Настройки TCP для минимальной задержки
- Улучшенные параметры BBR3
- Оптимизированный планировщик очереди (fq_pie)

### Параметры ядра

- TCP BBR3 конгестия
- ECN (Explicit Congestion Notification)
- Оптимизированные таймауты TCP
- Улучшенная обработка сетевых очередей

## 📊 Мониторинг

Для проверки статуса BBR после установки:

```bash
# Проверка алгоритма конгестии
sysctl net.ipv4.tcp_congestion_control

# Проверка планировщика очереди
sysctl net.core.default_qdisc

# Полная проверка конфигурации
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -c
```

## 🔍 Логирование

- Основной лог: `/var/log/server-scripts/server-scripts.log`
- Модули: `/usr/local/server-scripts/modules/`
- Конфигурация: `/etc/sysctl.d/99-xanmod-bbr.conf`

## 🆘 Устранение неполадок

1. **Ошибка при установке ядра:**
   - Проверьте свободное место: `df -h /`
   - Проверьте подключение к интернету
   - Просмотрите логи: `cat /var/log/server-scripts/server-scripts.log`

2. **BBR не активирован после установки:**
   - Запустите проверку: `sudo bash -s -- -c`
   - Проверьте параметры GRUB
   - Перезагрузите систему

3. **Проблемы с производительностью:**
   - Запустите bbr_info.sh для диагностики
   - Проверьте текущие настройки сети
   - При необходимости выполните переустановку

## 📄 Лицензия

MIT License

## 🤝 Поддержка

- GitHub Issues: [Server_scripts Issues](https://github.com/gopnikgame/Server_scripts/issues)
- Email: gopnikgame@example.com

## 📅 История изменений

### v1.0.1 (2025-02-20)
- Добавлена автоматическая коррекция настроек в bbr_info.sh
- Улучшена система обновления модулей
- Добавлены новые параметры оптимизации
- Исправлены ошибки в процессе установки

### v1.0.0 (2025-02-15)
- Первоначальный релиз
- Базовая функциональность установки XanMod
- Основные проверки BBR
