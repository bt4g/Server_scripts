# 🚀 Server Scripts Manager

![Version](https://img.shields.io/badge/version-1.0.3-blue)
![Updated](https://img.shields.io/badge/updated-2025--02--20-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

## 📋 Описание

Набор скриптов для автоматизированной настройки и оптимизации серверов на базе Ubuntu. Включает в себя:

- 🔧 Первоначальную настройку Ubuntu 24.04
- 🚄 Установку XanMod Kernel с BBR3
- 📊 Мониторинг и настройку BBR
- 🛡️ Расширенную настройку безопасности

## ⚡ Быстрая установка

```bash
wget -qO server_launcher.sh https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh && chmod +x server_launcher.sh && sudo ./server_launcher.sh
```

## 🛠️ Модули

### 1. Первоначальная настройка Ubuntu (ubuntu_pre_install.sh)

- ✅ Обновление системы
- 📦 Установка базовых пакетов
- 🔒 Настройка SSH с ключевой аутентификацией
- 🛡️ Настройка UFW
- 🌐 Оптимизация DNS (Google, Cloudflare, AdGuard)
- ⚙️ Системная оптимизация

### 2. XanMod Kernel (install_xanmod.sh)

- 🚄 Установка оптимизированного ядра
- 📈 Включение BBR3
- ⚡ Улучшение производительности

### 3. BBR Info (bbr_info.sh)

- 📊 Мониторинг состояния BBR
- 🔍 Проверка конфигурации
- 📈 Статистика работы

## 🔒 Безопасность

- Отключение парольной аутентификации SSH
- Блокировка подозрительных IP-адресов
- Оптимизированные правила файрволла
- DNS через DoH (DNS-over-HTTPS)

## 📋 Системные требования

- Ubuntu 24.04 или новее
- Минимум 5GB свободного места
- Root-доступ
- Подключение к интернету

## 🔧 Параметры установки

После установки скрипт создает:
- Директорию скриптов: `/root/server-scripts`
- Модули: `/usr/local/server-scripts/modules`
- Логи: `/var/log/server-scripts`
- Бэкапы: `/root/config_backup_[date]`

## 📝 Логирование

- Основной лог: `/var/log/server-scripts/server-scripts.log`
- Бэкапы конфигураций: `/root/config_backup_[date]`
- Информация о системе: `/root/system_setup_info.txt`

## 🚨 Важные замечания

1. **SSH доступ**: После установки доступ по паролю будет отключен
2. **Файрволл**: По умолчанию открыты только порты SSH (22), HTTP (80) и HTTPS (443)
3. **DNS**: Настроен с использованием DoH для повышенной безопасности
4. **Kernel**: При установке XanMod потребуется перезагрузка

## 🆘 Устранение неполадок

### Проблемы с SSH

```bash
# Проверка статуса SSH
systemctl status ssh

# Просмотр логов SSH
tail -f /var/log/auth.log
```

### Проблемы с DNS

```bash
# Проверка DNS
systemctl status systemd-resolved
cat /etc/resolv.conf
```

### Проблемы с файрволлом

```bash
# Проверка статуса UFW
ufw status verbose

# Просмотр правил
iptables -L
```

## 📄 Лицензия

MIT License © 2025 gopnikgame