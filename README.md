# 🚀 Server Scripts Manager v1.0.12

![Version](https://img.shields.io/badge/version-1.0.12-blue)
![Updated](https://img.shields.io/badge/updated-2025--06--11-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

## 📋 О проекте

Автоматизированный комплекс скриптов для настройки и оптимизации серверов на базе Ubuntu 24.04. Разработан с учетом лучших практик безопасности и производительности.

## ⚡ Быстрая установка

```bash
wget -qO server_launcher.sh https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh && chmod +x server_launcher.sh && sudo ./server_launcher.sh
```

## 🛠️ Основные компоненты

### 1. Server Launcher (server_launcher.sh)
- 🎯 Управление модулями
- 🔄 Автоматическое обновление
- 📊 Мониторинг состояния
- 🎨 Улучшенный интерфейс с цветным выводом

### 2. Первоначальная настройка Ubuntu (ubuntu_pre_install.sh)
- 📦 Установка и настройка базовых компонентов
- 🔒 Расширенная конфигурация безопасности
  - SSH с ключевой аутентификацией
  - Блокировка нежелательных AS
- 🌐 DNS через DoH (DNS-over-HTTPS)
  - Google DNS (основной)
  - Cloudflare (резервный)
  - AdGuard DNS (резервный)
- ⚙️ Оптимизация системных параметров

### 3. XanMod Kernel (install_xanmod.sh)
- 🚄 Установка оптимизированного ядра версии 1.2.1
- 📈 Настройка BBR3
- ⚡ Оптимизация производительности
- 🌐 Поддержка версий ядра 6.14 и 6.15
- 🔄 Планировщик очереди fq_pie
- ⚙️ Оптимизации для сетей 10Gbit+
- 🔒 ECN и оптимизация TCP

### 4. BBR Monitor (bbr_info.sh)
- 📊 Мониторинг BBR
- 🔍 Диагностика
- 📈 Статистика производительности

## 📋 Требования

- Ubuntu 24.04 LTS
- Минимум 5GB свободного места
- Root-доступ
- Интернет-подключение

## 🔧 Структура установки

```plaintext
/
├── root/
│   ├── server-scripts/           # Основная директория
│   └── config_backup_[date]/     # Резервные копии
├── usr/
│   └── local/
│       └── server-scripts/
│           └── modules/          # Модули системы
└── var/
    └── log/
        └── server-scripts/       # Логи
```

## 🛡️ Безопасность

### SSH настройки
- ✅ Только ключевая аутентификация
- ❌ Отключен root-доступ по паролю
- ⏱️ Таймаут входа: 30 секунд
- 🔄 Максимум попыток: 3

### Файрволл (UFW)
- 📝 Базовые правила:
  - SSH (22/tcp)
  - HTTP (80/tcp)
  - HTTPS (443/tcp)
- 🚫 Блокировка нежелательных AS
- 🔒 Режим: deny incoming, allow outgoing

### DNS безопасность
- 🔐 DNS-over-HTTPS
- ✅ DNSSEC включен
- 🔄 Резервные DNS-серверы
- 📝 Кеширование включено

## 📝 Логирование

### Основные файлы
- Системный лог: `/var/log/server-scripts/server-scripts.log`
- Бэкапы: `/root/config_backup_[timestamp]/`
- Конфигурация: `/root/system_setup_info.txt`

### Мониторинг
```bash
# Просмотр логов в реальном времени
tail -f /var/log/server-scripts/server-scripts.log

# Статус служб
systemctl status ssh systemd-resolved fail2ban
```

## 🆘 Устранение неполадок

### Проблемы с SSH
```bash
# Проверка конфигурации
ssh -T -v root@your_server

# Проверка прав ключей
ls -la ~/.ssh/
chmod 600 ~/.ssh/authorized_keys
```

### DNS проблемы
```bash
# Проверка резолвера
resolvectl status

# Тест DNS
dig @8.8.8.8 google.com
```

### Проблемы с ядром
```bash
# Проверка версии
uname -r

# Статус BBR
sysctl net.ipv4.tcp_congestion_control
```

# Проверка ECN
sysctl net.ipv4.tcp_ecn
## 🔄 Обновления

Для обновления всех компонентов:
1. Запустите launcher
2. Выберите "Обновить все модули"
3. Дождитесь завершения
4. При необходимости перезагрузите систему

## 📜 Лицензия

MIT License © 2025 gopnikgame

## 🤝 Поддержка

- GitHub Issues: [Server_scripts/issues](https://github.com/gopnikgame/Server_scripts/issues)
- Документация: [Wiki](https://github.com/gopnikgame/Server_scripts/wiki)

## 🔄 Последнее обновление

- Версия: 1.0.12
- Дата: 2025-06-11
- Автор: gopnikgame