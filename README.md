```markdown
# Xanmod Kernel Installer with BBR3

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Shell Script](https://img.shields.io/badge/Shell_Script-4EAA25?logo=gnu-bash&logoColor=white)

Автоматическая установка ядра Xanmod с оптимизированными настройками TCP BBR3 для Ubuntu/Debian

**Часть проекта [Server Scripts](https://github.com/gopnikgame/Server_scripts)**

## ✨ Особенности

- ✅ Автоматическая установка последней версии ядра Xanmod
- 🚀 Оптимизированная настройка TCP BBR3 (из документации Xanmod)
- 🔄 Полная поддержка восстановления системы (откат ядра)
- 📦 Резервное копирование текущей конфигурации ядра
- 📊 Проверка системных требований:
  - Поддержка CPU архитектуры (PSABI)
  - Свободное место на диске
  - Интернет-соединение
- 📝 Детальное логирование всех операций
```
## 📋 Требования

- Операционная система: Ubuntu 20.04+/Debian 10+
- Архитектура: x86_64
- Права: Требуются права root

## 🛠 Установка

```bash
# Скачать скрипт
wget https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/xanmod_installer.sh

# Дать права на выполнение
chmod +x xanmod_installer.sh

# Запустить установку
sudo ./xanmod_installer.sh
```

## 🚀 Использование

### Стандартная установка
Скрипт выполнит установку в 3 этапа с автоматическими перезагрузками:
1. Обновление системы и подготовка
2. Установка ядра Xanmod
3. Настройка BBR3 и финальная очистка

```bash
sudo ./xanmod_installer.sh
```

### Восстановление системы
Для отката к оригинальному ядру:
```bash
sudo ./xanmod_installer.sh --restore
```

## 🔍 Проверка BBR3
После успешной установки проверьте:
```bash
# Версию ядра
uname -r

# Активный алгоритм Congestion Control
sysctl net.ipv4.tcp_congestion_control

# Тип qdisc
sysctl net.core.default_qdisc

# Подробная информация о BBR
dmesg | grep -i bbr
```

## 🗂 Структура файлов
- `/var/log/xanmod_install.log` - лог установки
- `/var/backup/kernel_backup` - резервные копии ядра
- `/etc/sysctl.d/99-bbr.conf` - конфигурация BBR3

## ⚠️ Важно
- Скрипт выполнит 2 автоматические перезагрузки
- Не прерывайте процесс установки
- Резервная копия автоматически удаляется после успешной установки

## 📜 Лицензия
Этот проект распространяется под лицензией MIT. Подробности см. в файле [LICENSE](https://github.com/gopnikgame/Server_scripts/blob/main/LICENSE).

---

**Поддержка и вклад**  
[Сообщить об ошибке](https://github.com/gopnikgame/Server_scripts/issues) | [Инструкция по вкладу](https://github.com/gopnikgame/Server_scripts/blob/main/CONTRIBUTING.md)

---

> 🔄 Часть коллекции серверных скриптов:  
> [https://github.com/gopnikgame/Server_scripts](https://github.com/gopnikgame/Server_scripts)
```

### Основные изменения:
1. Обновлены все ссылки на репозиторий:
   ```diff
   - https://github.com/yourusername/xanmod-installer
   + https://github.com/gopnikgame/Server_scripts
   ```

2. Добавлен баннер проекта в начало:
   ```markdown
   **Часть проекта [Server Scripts](https://github.com/gopnikgame/Server_scripts)**
   ```

3. Обновлены прямые ссылки на файлы:
   - Установка: `wget` ссылка на raw-файл
   - Лицензия: прямая ссылка на файл LICENSE
   - CONTRIBUTING.md: ссылка на файл в репозитории

4. Добавлен финальный блок с ссылкой на коллекцию скриптов:
   ```markdown
   > 🔄 Часть коллекции серверных скриптов:  
   > [https://github.com/gopnikgame/Server_scripts](https://github.com/gopnikgame/Server_scripts)
   ```

5. Единообразное оформление всех URL в стиле проекта