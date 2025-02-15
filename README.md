# Server Scripts Collection

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-1.0.0-green.svg)
![XanMod](https://img.shields.io/badge/XanMod-supported-brightgreen.svg)

Коллекция скриптов для оптимизации и настройки серверов Linux.

## 🚀 Быстрый старт

### Установка XanMod и BBR3

```bash
curl -fsSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/install_xanmod.sh -o /tmp/install_xanmod.sh && \
sed -i "s/CURRENT_DATE=.*$/CURRENT_DATE=\"2025-02-15 08:34:54\"/" /tmp/install_xanmod.sh && \
sed -i "s/CURRENT_USER=.*$/CURRENT_USER=\"gopnikgame\"/" /tmp/install_xanmod.sh && \
sudo bash /tmp/install_xanmod.sh
```

### Проверка конфигурации BBR

```bash
curl -fsSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/bbr_info.sh | sed '1a\
# Функция логирования\
log() {\
    echo -e "\\033[1;34m[$(date '\''+%Y-%m-%d %H:%M:%S'\'')]\\033[0m - $1"\
}\
' > /tmp/bbr_info.sh && \
sed -i "s/CURRENT_DATE=.*$/CURRENT_DATE=\"2025-02-15 08:34:54\"/" /tmp/bbr_info.sh && \
sed -i "s/CURRENT_USER=.*$/CURRENT_USER=\"gopnikgame\"/" /tmp/bbr_info.sh && \
chmod +x /tmp/bbr_info.sh && \
sudo bash /tmp/bbr_info.sh
```

## 📋 Описание

Репозиторий содержит скрипты для:
- Установки и настройки ядра XanMod
- Оптимизации TCP с использованием BBR3
- Мониторинга сетевых параметров

## ✨ Возможности

### install_xanmod.sh
- Автоматическая установка ядра XanMod
- Оптимизация под архитектуру процессора (x64v1-v4)
- Настройка BBR3 и оптимизация сетевого стека
- Автоматическое определение оптимальных параметров

### bbr_info.sh
- Проверка текущего алгоритма управления перегрузкой
- Отображение доступных алгоритмов
- Мониторинг сетевых параметров
- Отображение статистики сети

## 🔧 Системные требования

- Debian/Ubuntu
- Архитектура x86_64
- Минимум 2 ГБ свободного места
- Права root

## 📦 Установка

1. Скачайте скрипт установки:
```bash
curl -fsSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/install_xanmod.sh -o install_xanmod.sh
```

2. Сделайте скрипт исполняемым:
```bash
chmod +x install_xanmod.sh
```

3. Запустите установку:
```bash
sudo ./install_xanmod.sh
```

## 🔍 Проверка работы

После установки и перезагрузки проверьте конфигурацию:

```bash
# Проверка версии ядра
uname -r

# Проверка BBR
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc

# Полная проверка
./bbr_info.sh
```

## 📊 Ожидаемый вывод

```
[2025-02-15 08:34:54] - Checking TCP congestion control configuration...
[2025-02-15 08:34:54] - Current congestion control: bbr3
[2025-02-15 08:34:54] - Available algorithms: reno cubic bbr bbr3
[2025-02-15 08:34:54] - Current qdisc: fq_pie
```

## 🔄 Обновление

Для обновления скриптов используйте:

```bash
curl -fsSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/install_xanmod.sh -o /tmp/install_xanmod.sh && \
sudo bash /tmp/install_xanmod.sh
```

## ⚠️ Важные замечания

1. Перед установкой создайте резервную копию важных данных
2. После установки требуется перезагрузка
3. При обновлении ядра рекомендуется повторная проверка настроек

## 🤝 Вклад в развитие

Мы приветствуем ваш вклад в развитие проекта! Создавайте issues и pull requests.

## 📜 Лицензия

MIT License - [LICENSE](LICENSE)

## 👤 Автор

**gopnikgame**
- GitHub: [@gopnikgame](https://github.com/gopnikgame)
- Created: 2025-02-15 08:34:54 UTC
- Last Modified: 2025-02-15 08:34:54 UTC

## 💬 Поддержка

Если у вас возникли проблемы или вопросы:
1. Создайте issue в репозитории
2. Опишите проблему и приложите результат выполнения `bbr_info.sh`
3. Укажите версию используемой операционной системы