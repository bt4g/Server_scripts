
```markdown 
# Server Scripts Collection
Коллекция скриптов для оптимизации и настройки серверов Linux.

## 🚀 Быстрый старт

### Установка XanMod и BBR3

```bash
curl -fsSL https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/install_xanmod.sh -o /tmp/install_xanmod.sh && \
sed -i "s/CURRENT_DATE=.*$/CURRENT_DATE=\"$(date -u '+%Y-%m-%d %H:%M:%S')\"/" /tmp/install_xanmod.sh && \
sed -i "s/CURRENT_USER=.*$/CURRENT_USER=\"$(whoami)\"/" /tmp/install_xanmod.sh && \
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
sed -i "s/CURRENT_DATE=.*$/CURRENT_DATE=\"$(date -u '+%Y-%m-%d %H:%M:%S')\"/" /tmp/bbr_info.sh && \
sed -i "s/CURRENT_USER=.*$/CURRENT_USER=\"$(whoami)\"/" /tmp/bbr_info.sh && \
chmod +x /tmp/bbr_info.sh && \
sudo bash /tmp/bbr_info.sh
```
## ⚠️ Важное замечание о скрипте
Если скрипт установил ядро и не перезагрузился а выдал ошибку, перезагрузите в ручную 
и запустите скрипт заново. он доустановит то что не установил. так де после окончания установки
сами перезагрузите сервер чтобы конфигурация BBR3 заработала.

Если скрвер во время работы скрипта выдал предупреждение о перезагрузке и перезагрущился, 
а скрипт после запуска предлагает переустановить ядро - значит система полностью настроена.

## ⚠️ Важное замечание о BBR3 в ядре XanMod

В ядре XanMod BBR3 имеет некоторые особенности отображения:
1. BBR3 отображается как "bbr" в выводе `sysctl net.ipv4.tcp_congestion_control`
2. Определить использование BBR3 можно по следующим признакам:
   - Версия модуля: `modinfo tcp_bbr` показывает `version: 3`
   - Планировщик очереди: `net.core.default_qdisc` установлен как `fq_pie`

Скрипт `bbr_info.sh` учитывает эти особенности и корректно определяет версию BBR.

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
- Определение версии BBR (v1/v3)

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
[2025-02-15 14:12:15] - Checking TCP congestion control configuration...
[2025-02-15 14:12:15] - Current congestion control: bbr
[2025-02-15 14:12:15] - BBRv3 detected (module version: 3, qdisc: fq_pie)
[2025-02-15 14:12:15] - Available algorithms: reno cubic bbr bbr3
[2025-02-15 14:12:15] - Current qdisc: fq_pie
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
4. BBR3 в ядре XanMod отображается как "bbr", это нормальное поведение

## 🤝 Вклад в развитие

Мы приветствуем ваш вклад в развитие проекта! Создавайте issues и pull requests.

## 📜 Лицензия

MIT License - [LICENSE](LICENSE)

## 👤 Автор

**gopnikgame**
- GitHub: [@gopnikgame](https://github.com/gopnikgame)
- Created: 2025-02-15 14:12:15 UTC
- Last Modified: 2025-02-15 14:12:15 UTC

