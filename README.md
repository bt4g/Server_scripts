# Server Scripts Collection

![Last Updated](https://img.shields.io/badge/Last%20Updated-2025--02--20-blue)
![Version](https://img.shields.io/badge/Version-1.0.2-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## 📝 Описание

Коллекция скриптов для автоматизации настройки и оптимизации серверов на базе Ubuntu/Debian.

## 🚀 Быстрый старт

### Базовое использование

```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- [опция]
```

### Доступные опции

| Опция | Описание |
|-------|----------|
| `-p, --preinstall` | Первоначальная настройка Ubuntu 24.04 |
| `-i, --install` | Установка XanMod Kernel с BBR3 |
| `-c, --check` | Проверка и настройка конфигурации BBR |
| `-u, --update` | Обновить все модули |
| `-h, --help` | Показать справку |

### Примеры использования

#### Первоначальная настройка Ubuntu 24.04
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -p
```

#### Установка XanMod Kernel
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -i
```

#### Проверка BBR
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/server_launcher.sh | sudo bash -s -- -c
```

## 📦 Модули

### ubuntu_pre_install.sh
- Обновление системы
- Настройка русской локали
- Настройка DNS (DNSSEC, DoH, кеширование)
- Установка базовых пакетов
- Настройка безопасности
- Оптимизация системных параметров

### install_xanmod.sh
- Установка XanMod ядра
- Настройка BBR3
- Оптимизация производительности

### bbr_info.sh
- Проверка конфигурации BBR
- Информация о текущем ядре
- Статус TCP конгестии

## 📋 Системные требования

- Ubuntu 24.04 или совместимый дистрибутив
- Права суперпользователя (root)
- Доступ в интернет
- Минимум 5GB свободного места

## 🛠 Технические детали

### Структура проекта
```
/usr/local/server-scripts/
├── modules/
│   ├── ubuntu_pre_install.sh
│   ├── install_xanmod.sh
│   └── bbr_info.sh
└── logs/
    └── server-scripts.log
```

### Логирование
- Все действия логируются в `/var/log/server-scripts/server-scripts.log`
- Резервные копии конфигураций сохраняются в `/root/config_backup_[timestamp]`

## 🔒 Безопасность

- Все скрипты используют проверку root прав
- Создаются резервные копии важных конфигураций
- Реализован механизм отката изменений при ошибках
- Проверка целостности загружаемых модулей

## 📝 Changelog

### Version 1.0.2 (2025-02-20)
- Добавлен модуль первоначальной настройки Ubuntu 24.04
- Улучшена система логирования
- Добавлены дополнительные проверки безопасности

### Version 1.0.1 (2025-02-20)
- Добавлена установка XanMod ядра
- Реализована проверка BBR конфигурации
- Улучшена обработка ошибок

### Version 1.0.0 (2025-02-20)
- Первый релиз
- Базовая функциональность
- Система модулей

## 👥 Участие в разработке

1. Fork репозитория
2. Создайте ветку для новой функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Push в ветку (`git push origin feature/amazing-feature`)
5. Создайте Pull Request

## 📄 Лицензия

Распространяется под лицензией MIT. Смотрите файл `LICENSE` для дополнительной информации.

## ✍️ Автор

**gopnikgame**
- GitHub: [@gopnikgame](https://github.com/gopnikgame)

## 🙏 Благодарности

- Сообществу Linux
- Разработчикам XanMod kernel
- Всем участникам проекта

## 📞 Поддержка

При возникновении проблем создавайте issue в репозитории проекта.