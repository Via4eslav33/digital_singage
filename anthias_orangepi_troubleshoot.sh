#!/bin/bash

# Скрипт усунення проблем Anthias на Orange Pi Zero 3
# Цей скрипт допомагає вирішити найпоширеніші проблеми

set -e

ANTHIAS_DIR="/home/$USER/screenly"
LOG_FILE="/tmp/anthias_troubleshoot.log"

echo "=========================================="
echo "Anthias Orange Pi Troubleshooter"
echo "=========================================="

# Логування функція
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функція для перевірки та виправлення Docker проблем
fix_docker_issues() {
    log_message "Перевірка Docker проблем..."
    
    # Перезапуск Docker сервісу
    if ! systemctl is-active --quiet docker; then
        log_message "Docker не активний, запуск..."
        sudo systemctl start docker
        sleep 3
    fi
    
    # Перевірка Docker socket
    if [ ! -S /var/run/docker.sock ]; then
        log_message "Docker socket не знайдено, перезапуск..."
        sudo systemctl restart docker
        sleep 5
    fi
    
    # Очистка зависших контейнерів
    DEAD_CONTAINERS=$(docker ps -a -f status=exited -f status=dead -q 2>/dev/null || true)
    if [ ! -z "$DEAD_CONTAINERS" ]; then
        log_message "Очистка зависших контейнерів..."
        docker rm $DEAD_CONTAINERS 2>/dev/null || true
    fi
    
    # Очистка невикористаних образів
    log_message "Очистка невикористаних Docker образів..."
    docker system prune -f >/dev/null 2>&1 || true
    
    log_message "Docker проблеми виправлені"
}

# Функція для виправлення проблем з правами доступу
fix_permissions() {
    log_message "Виправлення прав доступу..."
    
    # Права доступу до Anthias директорії
    sudo chown -R $USER:$USER "$ANTHIAS_DIR" 2>/dev/null || true
    
    # Права доступу до Docker socket
    sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    
    # Додавання користувача до потрібних груп
    sudo usermod -aG docker,video,audio $USER 2>/dev/null || true
    
    # Права доступу до пристроїв
    sudo chmod 666 /dev/fb* 2>/dev/null || true
    sudo chmod 666 /dev/mali* 2>/dev/null || true
    
    log_message "Права доступу виправлені"
}

# Функція для виправлення мережевих проблем
fix_network_issues() {
    log_message "Перевірка мережевих проблем..."
    
    # Перевірка інтернет з'єднання
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        log_message "Проблема з інтернет з'єднанням"
        
        # Перезапуск NetworkManager
        if systemctl is-active --quiet NetworkManager; then
            log_message "Перезапуск NetworkManager..."
            sudo systemctl restart NetworkManager
            sleep 5
        fi
        
        # Перезапуск мережевих інтерфейсів
        log_message "Перезапуск мережевих інтерфейсів..."
        sudo ifdown --all 2>/dev/null || true
        sudo ifup --all 2>/dev/null || true
    fi
    
    log_message "Мережеві проблеми перевірені"
}

# Функція для виправлення проблем з відео
fix_video_issues() {
    log_message "Виправлення проблем з відео..."
    
    # Перевірка наявності framebuffer
    if [ ! -c /dev/fb0 ]; then
        log_message "Framebuffer /dev/fb0 не знайдено"
        
        # Спроба створити symlink якщо є інший fb
        for fb in /dev/fb*; do
            if [ -c "$fb" ]; then
                log_message "Знайдено $fb, створення symlink..."
                sudo ln -sf "$fb" /dev/fb0 2>/dev/null || true
                break
            fi
        done
    fi
    
    # Налаштування framebuffer
    if [ -c /dev/fb0 ]; then
        sudo chmod 666 /dev/fb0
        log_message "Framebuffer налаштовано"
    fi
    
    # Перевірка Mali GPU
    if [ -c /dev/mali0 ]; then
        sudo chmod 666 /dev/mali0
        log_message "Mali GPU знайдено та налаштовано"
    fi
    
    log_message "Проблеми з відео виправлені"
}

# Функція для виправлення проблем з пам'яттю
fix_memory_issues() {
    log_message "Оптимізація використання пам'яті..."
    
    # Очистка системних кешів
    sync
    echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    echo 2 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    # Перевірка та створення swap
    if ! swapon -s | grep -q /swapfile; then
        if [ -f /swapfile ]; then
            log_message "Активація swap файлу..."
            sudo swapon /swapfile 2>/dev/null || true
        else
            log_message "Створення swap файлу 512MB..."
            sudo fallocate -l 512M /swapfile 2>/dev/null || true
            sudo chmod 600 /swapfile 2>/dev/null || true
            sudo mkswap /swapfile >/dev/null 2>&1 || true
            sudo swapon /swapfile 2>/dev/null || true
            
            # Додавання до fstab якщо не існує
            if ! grep -q "/swapfile" /etc/fstab; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
            fi
        fi
    fi
    
    log_message "Пам'ять оптимізовано"
}

# Функція для перезапуску Anthias контейнерів
restart_anthias() {
    log_message "Перезапуск Anthias контейнерів..."
    
    cd "$ANTHIAS_DIR"
    
    # Зупинка контейнерів
    docker-compose down 2>/dev/null || true
    
    # Очікування
    sleep 5
    
    # Запуск контейнерів
    docker-compose up -d 2>/dev/null || {
        log_message "Проблема з docker-compose, спроба виправлення..."
        
        # Завантаження свіжих compose файлів
        wget -q https://raw.githubusercontent.com/Screenly/Anthias/master/docker-compose.yml -O docker-compose.yml.new
        if [ -f docker-compose.yml.new ]; then
            mv docker-compose.yml docker-compose.yml.backup
            mv docker-compose.yml.new docker-compose.yml
            log_message "docker-compose.yml оновлено"
        fi
        
        # Повторна спроба
        docker-compose up -d || log_message "Не вдалося запустити контейнери"
    }
    
    log_message "Anthias перезапущено"
}

# Функція для збирання діагностичної інформації
collect_diagnostics() {
    log_message "Збирання діагностичної інформації..."
    
    DIAG_FILE="/tmp/anthias_diagnostics_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "========== Anthias Orange Pi Diagnostics =========="
        echo "Date: $(date)"
        echo "User: $USER"
        echo ""
        
        echo "=== System Information ==="
        uname -a
        lsb_release -a 2>/dev/null || true
        cat /proc/version
        echo ""
        
        echo "=== Hardware Information ==="
        cat /proc/cpuinfo | grep -E "(processor|model name|Hardware|Revision)" || true
        cat /proc/meminfo | head -5
        echo ""
        
        echo "=== Device Tree ==="
        ls -la /proc/device-tree/ 2>/dev/null || echo "Device tree not available"
        cat /proc/device-tree/model 2>/dev/null || echo "Model info not available"
        echo ""
        
        echo "=== Storage ==="
        df -h
        echo ""
        
        echo "=== Memory Usage ==="
        free -h
        swapon -s || echo "No swap configured"
        echo ""
        
        echo "=== Network ==="
        ip addr show
        ping -c 1 google.com 2>&1 || echo "Internet connectivity issues"
        echo ""
        
        echo "=== Docker ==="
        docker --version
        systemctl status docker --no-pager -l
        docker ps -a
        docker images
        echo ""
        
        echo "=== Anthias Services ==="
        systemctl status anthias --no-pager -l 2>/dev/null || echo "Anthias service not configured"
        echo ""
        
        echo "=== Anthias Containers ==="
        cd "$ANTHIAS_DIR" 2>/dev/null && {
            docker-compose ps 2>/dev/null || echo "docker-compose not working"
            docker-compose logs --tail=50 2>/dev/null || echo "No container logs"
        } || echo "Anthias directory not found"
        echo ""
        
        echo "=== Video Devices ==="
        ls -la /dev/fb* 2>/dev/null || echo "No framebuffer devices"
        ls -la /dev/mali* 2>/dev/null || echo "No Mali devices"
        echo ""
        
        echo "=== X11 ==="
        echo "DISPLAY: $DISPLAY"
        ps aux | grep -E "(X|xinit|startx)" | grep -v grep || echo "No X11 processes"
        echo ""
        
        echo "=== Log Files ==="
        tail -50 /var/log/syslog 2>/dev/null || echo "Syslog not available"
        echo ""
        
    } > "$DIAG_FILE"
    
    log_message "Діагностика збережена у $DIAG_FILE"
    echo "$DIAG_FILE"
}

# Функція автоматичного виправлення
auto_fix() {
    log_message "Початок автоматичного виправлення проблем..."
    
    fix_docker_issues
    fix_permissions
    fix_network_issues
    fix_video_issues
    fix_memory_issues
    restart_anthias
    
    log_message "Автоматичне виправлення завершено"
}

# Інтерактивне меню
interactive_menu() {
    while true; do
        echo ""
        echo "=========================================="
        echo "Anthias Orange Pi Troubleshooter Menu"
        echo "=========================================="
        echo "1) Автоматичне виправлення всіх проблем"
        echo "2) Виправити Docker проблеми"
        echo "3) Виправити права доступу"
        echo "4) Виправити мережеві проблеми"
        echo "5) Виправити проблеми з відео"
        echo "6) Оптимізувати пам'ять"
        echo "7) Перезапустити Anthias"
        echo "8) Зібрати діагностику"
        echo "9) Показати статус системи"
        echo "0) Вихід"
        echo ""
        read -p "Оберіть опцію [0-9]: " choice
        
        case $choice in
            1) auto_fix ;;
            2) fix_docker_issues ;;
            3) fix_permissions ;;
            4) fix_network_issues ;;
            5) fix_video_issues ;;
            6) fix_memory_issues ;;
            7) restart_anthias ;;
            8) collect_diagnostics ;;
            9) show_status ;;
            0) echo "Вихід..."; break ;;
            *) echo "Невірний вибір. Спробуйте ще раз." ;;
        esac
    done
}

# Функція показу статусу
show_status() {
    echo ""
    echo "========== Поточний статус системи =========="
    
    echo "Docker: $(systemctl is-active docker 2>/dev/null || echo 'неактивний')"
    echo "NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'неактивний')"
    echo "Anthias Service: $(systemctl is-active anthias 2>/dev/null || echo 'не налаштований')"
    
    echo ""
    echo "Пам'ять:"
    free -h | head -2
    
    echo ""
    echo "Дисковий простір:"
    df -h / | tail -1
    
    echo ""
    echo "Anthias контейнери:"
    if [ -d "$ANTHIAS_DIR" ]; then
        cd "$ANTHIAS_DIR"
        docker-compose ps 2>/dev/null || echo "Не запущені або проблема з docker-compose"
    else
        echo "Anthias не встановлено"
    fi
}

# Основна функція
main() {
    if [ "$EUID" -eq 0 ]; then
        echo "Не запускайте цей скрипт з правами root!"
        exit 1
    fi
    
    # Створення лог файлу
    touch "$LOG_FILE"
    log_message "Початок сесії troubleshooting"
    
    case "${1:-}" in
        --auto|-a)
            auto_fix
            ;;
        --diagnose|-d)
            collect_diagnostics
            ;;
        --status|-s)
            show_status
            ;;
        --help|-h)
            echo "Використання: $0 [опція]"
            echo "Опції:"
            echo "  --auto, -a      Автоматичне виправлення"
            echo "  --diagnose, -d  Збір діагностики"
            echo "  --status, -s    Показати статус"
            echo "  --help, -h      Показати допомогу"
            echo "  (без опцій)     Інтерактивне меню"
            ;;
        *)
            interactive_menu
            ;;
    esac
    
    log_message "Сесія troubleshooting завершена"
    echo ""
    echo "Лог збережено у: $LOG_FILE"
}