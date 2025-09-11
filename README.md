# Anthias Digital Signage for Orange Pi Zero 3

Цей репозиторій містить модифікований інсталятор Anthias (колишній Screenly OSE) для роботи на Orange Pi Zero 3 з Armbian або Debian/Ubuntu.

## Огляд

Anthias - це популярна платформа для цифрових вивісок з відкритим кодом, яка спочатку була розроблена для Raspberry Pi. Цей модифікований інсталятор адаптує Anthias для роботи на Orange Pi Zero 3, вирішуючи проблеми сумісності та оптимізуючи продуктивність.

## Підтримувані системи

- **Orange Pi Zero 3** (1GB/1.5GB/4GB)
- **ОС**: Armbian Bookworm, Debian 12, Ubuntu 22.04/24.04
- **Архітектура**: ARM64 (aarch64)

## Попередні вимоги

### Апаратні вимоги
- Orange Pi Zero 3 (рекомендується мінімум 1GB RAM)
- MicroSD карта (мінімум 16GB, рекомендується 32GB)
- Стабільне живлення 5V/3A
- HDMI дисплей або підключений екран
- Інтернет з'єднання (WiFi або Ethernet через USB адаптер)

### Програмні вимоги
- Свіжо встановлена Armbian Bookworm або Debian 12+
- Користувач з правами sudo (не root)
- Доступ до інтернету

## Встановлення

### Крок 1: Підготовка системи

Оновіть систему до останньої версії:

```bash
sudo apt update && sudo apt upgrade -y
```

Встановіть базові інструменти:

```bash
sudo apt install -y curl wget git
```

### Крок 2: Завантаження скриптів

Завантажте модифікований інсталятор:

```bash
wget https://github.com/Via4eslav33/digital_singage/blob/main/anthias_orangepi_installer.sh
chmod +x anthias-orangepi-installer.sh
```

Завантажте допоміжні скрипти:

```bash
wget https://github.com/Via4eslav33/digital_singage/blob/main/anthias_orangepi_postinstall.sh
wget https://github.com/Via4eslav33/digital_singage/blob/main/anthias_orangepi_troubleshoot.sh
chmod +x anthias-orangepi-*.sh
```

### Крок 3: Запуск інсталяції

⚠️ **ВАЖЛИВО**: Не запускайте скрипт з правами root!

```bash
./anthias-orangepi-installer.sh
```

Інсталятор запитає вас про:
- Керування мережею через Anthias
- Версію для встановлення (latest або specific tag)
- Чи робити повне оновлення системи

### Крок 4: Післяінсталяційне налаштування

Після перезавантаження запустіть:

```bash
./anthias-orangepi-postinstall.sh
```

Цей скрипт налаштує:
- Docker контейнери
- Відео драйвери
- X11 сервер
- Системні служби
- Оптимізацію пам'яті

### Крок 5: Перевірка роботи

Після завершення налаштування:

```bash
# Перезавантаження системи
sudo reboot

# Після перезавантаження перевірте статус
sudo systemctl status anthias
sudo docker ps

# Перевірте веб-інтерфейс
# Відкрийте браузер і перейдіть на IP адресу вашого Orange Pi
http://[IP-адреса-Orange-Pi]
```

## Усунення проблем

### Автоматичне виправлення

Для швидкого виправлення найпоширеніших проблем:

```bash
./anthias-orangepi-troubleshoot.sh --auto
```

### Інтерактивне меню усунення проблем

```bash
./anthias-orangepi-troubleshoot.sh
```

### Збір діагностичної інформації

```bash
./anthias-orangepi-troubleshoot.sh --diagnose
```

### Найпоширеніші проблеми та рішення

#### 1. Контейнери не запускаються

**Симптоми**: `docker ps` показує, що контейнери не працюють

**Рішення**:
```bash
# Перевірте логи Docker
sudo journalctl -u docker -f

# Перезапустіть Docker
sudo systemctl restart docker

# Перезапустіть Anthias
cd ~/screenly
docker-compose down
docker-compose up -d
```

#### 2. Веб-інтерфейс недоступний

**Симптоми**: Не можете відкрити http://[IP-адреса]

**Рішення**:
```bash
# Перевірте мережеве з'єднання
ip addr show

# Перевірте порти
sudo netstat -tlnp | grep :80

# Перезапустіть сервіс
sudo systemctl restart anthias
```

#### 3. Проблеми з відображенням

**Симптоми**: Чорний екран або неправильне відображення

**Рішення**:
```bash
# Перевірте framebuffer
ls -la /dev/fb*

# Перевірте X11 процеси
ps aux | grep X

# Налаштуйте дисплей
export DISPLAY=:0
xset -dpms
xset s off
```

#### 4. Недостатньо пам'яті

**Симптоми**: Система повільна, контейнери вилітають

**Рішення**:
```bash
# Перевірте використання пам'яті
free -h

# Створіть swap файл
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Додайте до fstab
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Конфігурація

### Налаштування відео

Для оптимальної якості відео на Orange Pi Zero 3:

```bash
# Відредагуйте конфігурацію
nano ~/screenly/.env

# Додайте/змініть наступні параметри:
VIDEO_DEVICE=/dev/fb0
DISPLAY=:0
QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0
```

### Налаштування мережі

Для WiFi конфігурації:

```bash
# Використовуйте NetworkManager
sudo nmtui

# Або через командний рядок
sudo nmcli dev wifi connect "SSID" password "пароль"
```

### Налаштування автозапуску

Для автоматичного запуску Anthias при завантаженні:

```bash
# Активуйте сервіс
sudo systemctl enable anthias

# Перевірте статус
sudo systemctl status anthias
```

## Оптимізація продуктивності

### Для Orange Pi Zero 3 1GB

```bash
# Зменшіть використання пам'яті
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# Оптимізуйте Docker
echo '{"storage-driver": "overlay2", "log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}' | sudo tee /etc/docker/daemon.json

sudo systemctl restart docker
```

### Для кращої продуктивності відео

```bash
# Налаштування GPU
echo 'export MESA_GL_VERSION_OVERRIDE=2.1' | sudo tee -a /etc/environment
echo 'export MESA_GLSL_VERSION_OVERRIDE=120' | sudo tee -a /etc/environment
```

## Моніторинг

### Перевірка статусу системи

```bash
# Загальний статус
./anthias-orangepi-troubleshoot.sh --status

# Docker контейнери
docker ps

# Використання ресурсів
htop

# Логи системи
sudo journalctl -f
```

### Логи Anthias

```bash
cd ~/screenly

# Логи всіх контейнерів
docker-compose logs

# Логи конкретного контейнера
docker-compose logs server
docker-compose logs viewer
```

## Оновлення

### Оновлення Anthias

```bash
cd ~/screenly

# Оновіть код
git pull origin master

# Оновіть контейнери
./bin/upgrade_containers.sh
```

### Оновлення системи

```bash
# Оновлення пакетів
sudo apt update && sudo apt upgrade -y

# Оновлення Docker образів
docker system prune -f
cd ~/screenly
docker-compose pull
docker-compose up -d
```

## Відомі обмеження

1. **Продуктивність**: Orange Pi Zero 3 1GB може мати обмежену продуктивність з важкими медіа файлами
2. **4K відео**: Не рекомендується для 4K контенту
3. **Одночасні відео**: Обмеження на кількість одночасних відео потоків
4. **WebGL**: Можливі проблеми з складними WebGL анімаціями

## Підтримка

### Логи для звіту про помилки

При зверненні за допомогою обов'язково додайте:

```bash
# Збір діагностики
./anthias-orangepi-troubleshoot.sh --diagnose

# Системна інформація
uname -a
lsb_release -a
free -h
df -h

# Docker інформація
docker --version
docker-compose --version
docker ps -a
```

### Корисні команди

```bash
# Повний перезапуск Anthias
sudo systemctl stop anthias
docker-compose -f ~/screenly/docker-compose.yml down
docker system prune -f
sudo systemctl start anthias

# Скидання до заводських налаштувань
cd ~/screenly
docker-compose down -v
docker system prune -af
git reset --hard HEAD
docker-compose up -d
```

## Альтернативні рішення

Якщо у вас виникають постійні проблеми з продуктивністю:

1. **Розгляньте використання Orange Pi 5** для кращої продуктивності
2. **Використовуйте легший контент** (зображення замість відео)
3. **Зменшіть роздільну здатність дисплея**
4. **Використовуйте статичний контент** замість динамічного

## Внесок у проект

Ласкаво просимо вносити свій внесок! Будь ласка:

1. Форкните репозиторій
2. Створіть feature branch
3. Зробіть ваші зміни
4. Протестуйте на Orange Pi Zero 3
5. Створіть Pull Request

## Ліцензія

Цей проект розповсюджується під тією ж ліцензією, що й оригінальний Anthias проект.

## Подяки

- Команді Screenly за створення Anthias
- Спільноті Orange Pi за підтримку
- Всім, хто тестував та надавав зворотний зв'язок
