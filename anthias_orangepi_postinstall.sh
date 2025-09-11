#!/bin/bash

# Скрипт післяінсталяційного налаштування Anthias для ARM SBC
# Підтримує Orange Pi, ТВ бокси S905X3, Rock Pi, Banana Pi та інші ARM SBC
# Запускати після перезавантаження системи

set -e

USER_HOME="/home/$USER"
ANTHIAS_DIR="$USER_HOME/screenly"

echo "=========================================="
echo "Anthias ARM SBC Post-Install Setup"
echo "=========================================="

# Функція для визначення типу пристрою (копія з основного скрипта)
detect_device_info() {
    DEVICE_VENDOR=""
    DEVICE_MODEL=""
    DEVICE_SOC=""
    DEVICE_ARCH=$(uname -m)
    DEVICE_GPU=""
    
    if [ -f /proc/device-tree/model ]; then
        DEVICE_INFO=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
    fi
    
    if [ -f /proc/device-tree/compatible ]; then
        DEVICE_COMPATIBLE=$(cat /proc/device-tree/compatible 2>/dev/null | tr -d '\0')
    fi
    
    if [ -f /proc/cpuinfo ]; then
        DEVICE_SOC=$(grep -i "hardware\|model" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs 2>/dev/null || echo "")
    fi
    
    # Визначення GPU
    if [ -d /sys/devices/platform/ff400000.gpu ] || [ -d /sys/devices/platform/fde60000.gpu ]; then
        DEVICE_GPU="mali"
    elif [ -d /sys/devices/platform/*.gpu ] || [ -d /sys/class/devfreq/*gpu* ]; then
        DEVICE_GPU="generic"
    fi
    
    # Визначення вендора та моделі
    case "$DEVICE_INFO$DEVICE_COMPATIBLE" in
        *"Orange Pi"*|*"orangepi"*) DEVICE_#!/bin/bash

# Скрипт післяінсталяційного налаштування Anthias для Orange Pi Zero 3
# Запускати після перезавантаження системи

set -e

USER_HOME="/home/$USER"
ANTHIAS_DIR="$USER_HOME/screenly"

echo "=========================================="
echo "Anthias Orange Pi Post-Install Setup"
echo "=========================================="

# Функція для перевірки статусу Docker
check_docker() {
    echo "Перевірка стану Docker..."
    
    if ! systemctl is-active --quiet docker; then
        echo "Запуск Docker сервісу..."
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo "Проблеми з Docker. Спроба перезапуску..."
        sudo systemctl restart docker
        sleep 5
    fi
    
    # Додавання користувача до групи docker якщо потрібно
    if ! groups $USER | grep -q docker; then
        echo "Додавання $USER до групи docker..."
        sudo usermod -aG docker $USER
        echo "УВАГА: Потрібно повторно увійти в систему або перезавантажитись"
        echo "щоб зміни групи вступили в силу"
    fi
    
    echo "Docker статус: OK"
}

# Функція для налаштування GPU та відео
setup_gpu_video() {
    echo "Налаштування GPU та відео для Orange Pi..."
    
    # Створення групи video якщо не існує
    sudo groupadd -f video
    sudo usermod -aG video $USER
    
    # Перевірка чи є Mali GPU драйвери
    if [ -d /dev/mali* ] || [ -c /dev/mali* ]; then
        echo "Mali GPU виявлено"
        sudo chmod 666 /dev/mali* 2>/dev/null || true
    fi
    
    # Налаштування для Allwinner H618
    if grep -q "allwinner,sun50i-h618" /proc/device-tree/compatible 2>/dev/null; then
        echo "Allwinner H618 виявлено, налаштування специфічних параметрів..."
        
        # Встановлення змінних середовища для Mesa
        echo 'export MESA_GL_VERSION_OVERRIDE=2.1' | sudo tee -a /etc/environment
        echo 'export MESA_GLSL_VERSION_OVERRIDE=120' | sudo tee -a /etc/environment
    fi
}

# Функція для перевірки та виправлення контейнерів
fix_containers() {
    echo "Перевірка та виправлення Anthias контейнерів..."
    
    cd "$ANTHIAS_DIR"
    
    # Зупинка всіх контейнерів якщо працюють
    sudo docker-compose down 2>/dev/null || true
    
    # Очистка старих образів
    sudo docker system prune -f
    
    # Перевірка чи існує docker-compose.yml
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.production.yml" ]; then
        echo "Docker Compose файли не знайдені. Створення базової конфігурації..."
        
        # Завантаження останніх конфігураційних файлів
        wget -q https://raw.githubusercontent.com/Screenly/Anthias/master/docker-compose.yml -O docker-compose.yml
        wget -q https://raw.githubusercontent.com/Screenly/Anthias/master/docker-compose.production.yml -O docker-compose.production.yml
    fi
    
    # Створення .env файлу якщо не існує
    if [ ! -f ".env" ]; then
        echo "Створення .env файлу..."
        cat > .env << EOF
# Orange Pi Zero 3 специфічні налаштування
DEVICE_TYPE=pi3
ARCHITECTURE=$ARCHITECTURE
BALENA_DEVICE_TYPE=orangepi-zero3

# Базові налаштування Anthias
ANTHIAS_HOST=0.0.0.0
ANTHIAS_PORT=80
REDIS_HOST=redis
POSTGRES_HOST=postgres
POSTGRES_DB=screenly
POSTGRES_USER=screenly
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Налаштування відео для Orange Pi
VIDEO_DEVICE=/dev/fb0
DISPLAY=:0
EOF
    fi
    
    # Модифікація docker-compose.yml для Orange Pi
    if [ -f "docker-compose.yml" ]; then
        echo "Модифікація Docker Compose конфігурації для Orange Pi..."
        
        # Створення резервної копії
        cp docker-compose.yml docker-compose.yml.backup
        
        # Додавання налаштувань для Orange Pi
        cat > docker-compose.override.yml << 'EOF'
version: '3.8'
services:
  viewer:
    devices:
      - "/dev/fb0:/dev/fb0"
      - "/dev/mali0:/dev/mali0"
    environment:
      - DISPLAY=:0
      - QT_QPA_PLATFORM=linuxfb:fb=/dev/fb0
      - QT_QPA_FONTDIR=/usr/share/fonts
    privileged: true
    
  server:
    environment:
      - DEVICE_TYPE=orangepi
      
  redis:
    restart: unless-stopped
    
  postgres:
    restart: unless-stopped
EOF
    fi
}

# Функція для налаштування системних служб
setup_services() {
    echo "Налаштування системних служб..."
    
    # Створення systemd сервісу для Anthias
    sudo tee /etc/systemd/system/anthias.service > /dev/null << EOF
[Unit]
Description=Anthias Digital Signage
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$ANTHIAS_DIR
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

    # Включення автозапуску
    sudo systemctl daemon-reload
    sudo systemctl enable anthias.service
    
    echo "Systemd сервіс anthias створено та включено"
}

# Функція для налаштування X11 та дисплею
setup_display() {
    echo "Налаштування дисплею для Orange Pi..."
    
    # Встановлення X11 якщо не встановлено
    if ! command -v startx &> /dev/null; then
        echo "Встановлення X11..."
        sudo apt-get update
        sudo apt-get install -y xorg xserver-xorg-video-fbdev xinit
    fi
    
    # Створення базової X11 конфігурації
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/20-fbdev.conf > /dev/null << 'EOF'
Section "Device"
    Identifier "Mali FBDEV"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
    Option "SwapbuffersWait" "true"
EndSection
EOF

    # Автозапуск X11 для користувача
    if ! grep -q "startx" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Автозапуск X11 для Anthias" >> ~/.bashrc
        echo "if [ -z \"\$DISPLAY\" ] && [ \"\$(tty)\" = \"/dev/tty1\" ]; then" >> ~/.bashrc
        echo "    startx" >> ~/.bashrc
        echo "fi" >> ~/.bashrc
    fi
    
    # Створення .xinitrc
    cat > ~/.xinitrc << 'EOF'
#!/bin/sh
# Базова X11 конфігурація для Anthias на Orange Pi
xset -dpms
xset s off
xset s noblank

# Запуск браузера в повноекранному режиці (буде керуватись Anthias)
exec /bin/bash
EOF
    chmod +x ~/.xinitrc
}

# Функція для налаштування мережі
setup_network() {
    echo "Перевірка налаштувань мережі..."
    
    # Перевірка чи WiFi налаштовано
    if ip link show | grep -q wlan; then
        echo "WiFi адаптер знайдено"
        
        # Перевірка NetworkManager
        if systemctl is-active --quiet NetworkManager; then
            echo "NetworkManager активний"
        else
            echo "Запуск NetworkManager..."
            sudo systemctl start NetworkManager
            sudo systemctl enable NetworkManager
        fi
    fi
}

# Функція для перевірки пам'яті та оптимізації
optimize_memory() {
    echo "Оптимізація використання пам'яті..."
    
    # Створення swap файлу якщо немає
    if [ ! -f /swapfile ]; then
        echo "Створення swap файлу 512MB..."
        sudo fallocate -l 512M /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Додавання до fstab
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    
    # Налаштування swappiness для SBC
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
    
    # Очистка кешів
    sudo sync
    echo 1 | sudo tee /proc/sys/vm/drop_caches > /dev/null
}

# Функція для діагностики проблем
diagnose_issues() {
    echo ""
    echo "=========================================="
    echo "Діагностика системи"
    echo "=========================================="
    
    echo "1. Системна інформація:"
    echo "   - Архітектура: $(uname -m)"
    echo "   - Ядро: $(uname -r)"
    echo "   - Дистрибутив: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Невідомо')"
    echo ""
    
    echo "2. Пам'ять:"
    free -h
    echo ""
    
    echo "3. Дисковий простір:"
    df -h /
    echo ""
    
    echo "4. Docker статус:"
    if systemctl is-active --quiet docker; then
        echo "   Docker: Активний ✓"
        docker --version
    else
        echo "   Docker: Неактивний ✗"
    fi
    echo ""
    
    echo "5. Anthias контейнери:"
    cd "$ANTHIAS_DIR"
    if [ -f "docker-compose.yml" ]; then
        docker-compose ps 2>/dev/null || echo "   Контейнери не запущені"
    else
        echo "   docker-compose.yml не знайдено"
    fi
    echo ""
    
    echo "6. Мережеві інтерфейси:"
    ip addr show | grep -E "^[0-9]|inet " | head -10
    echo ""
    
    echo "7. Системні сервіси:"
    systemctl is-enabled anthias 2>/dev/null && echo "   anthias: enabled ✓" || echo "   anthias: не налаштовано ✗"
    systemctl is-active --quiet NetworkManager && echo "   NetworkManager: активний ✓" || echo "   NetworkManager: неактивний"
}

# Основна функція
main() {
    if [ "$EUID" -eq 0 ]; then
        echo "Не запускайте цей скрипт з правами root!"
        exit 1
    fi
    
    if [ ! -d "$ANTHIAS_DIR" ]; then
        echo "Директорія Anthias не знайдена. Спочатку запустіть основний інсталятор."
        exit 1
    fi
    
    echo "Початок післяінсталяційного налаштування..."
    echo ""
    
    check_docker
    setup_gpu_video
    fix_containers
    setup_services
    setup_display
    setup_network
    optimize_memory
    
    echo ""
    echo "=========================================="
    echo "Налаштування завершено!"
    echo "=========================================="
    echo ""
    echo "Наступні кроки:"
    echo "1. Перезавантажте систему: sudo reboot"
    echo "2. Після перезавантаження запустіть Anthias: sudo systemctl start anthias"
    echo "3. Перевірте статус: sudo systemctl status anthias"
    echo "4. Відкрийте веб-інтерфейс: http://$(hostname -I | awk '{print $1}')"
    echo ""
    echo "Для діагностики запустіть: $0 --diagnose"
    
    diagnose_issues
}

# Перевірка параметрів командного рядка
if [ "$1" == "--diagnose" ]; then
    diagnose_issues
    exit 0
fi

main