#!/bin/bash -e

# vim: tabstop=4 shiftwidth=4 softtabstop=4
# -*- sh-basic-offset: 4 -*-

# Модифікований інсталятор Anthias для Orange Pi Zero 3. Базований на оригінальному скрипті від Screenly/Anthias

set -euo pipefail

BRANCH="master"
ANSIBLE_PLAYBOOK_ARGS=()
REPOSITORY="https://github.com/Screenly/Anthias.git"
ANTHIAS_REPO_DIR="/home/${USER}/screenly"
GITHUB_API_REPO_URL="https://api.github.com/repos/Screenly/Anthias"
GITHUB_RELEASES_URL="https://github.com/Screenly/Anthias/releases"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Screenly/Anthias"
DOCKER_TAG="latest"
UPGRADE_SCRIPT_PATH="${ANTHIAS_REPO_DIR}/bin/upgrade_containers.sh"
ARCHITECTURE=$(uname -m)
DISTRO_VERSION=$(lsb_release -rs)

INTRO_MESSAGE=(
    "Anthias для Orange Pi Zero 3 (неофіційна версія)"
    "Цей скрипт адаптований для роботи з Orange Pi Zero 3 на Armbian/Debian."
    "Вам потрібна відокремлена Orange Pi та SD карта."
    ""
    "Коли буде запропоновано версію, ви можете вибрати:"
    "  - **latest:** Встановлює останню версію з гілки \`master\`."
    "  - **tag:** Встановлює закріплену версію на основі назви тегу."
    ""
    "Зауважте, що \`latest\` - це rolling release."
)
MANAGE_NETWORK_PROMPT=(
    "Чи хочете ви, щоб Anthias керував мережею для вас?"
)
VERSION_PROMPT=(
    "Яку версію Anthias ви хочете встановити?"
)
VERSION_PROMPT_CHOICES=(
    "latest"
    "tag"
)
SYSTEM_UPGRADE_PROMPT=(
    "Чи хочете ви також виконати повне оновлення системи?"
)
SUDO_ARGS=()

TITLE_TEXT=$(cat <<EOF
     @@@@@@@@@
  @@@@@@@@@@@@                 d8888          888    888      d8b
 @@@@@@@  @@@    @@           d88888          888    888      Y8P
@@@@@@@@@@@@@    @@@         d88P888          888    888
@@@@@@@@@@ @@   @@@@        d88P 888 88888b.  888888 88888b.  888  8888b.  .d8888b
@@@@@       @@@@@@@@       d88P  888 888 "88b 888    888 "88b 888     "88b 88K
@@@%:      :@@@@@@@@      d88P   888 888  888 888    888  888 888 .d888888 "Y8888b.
 @@-:::::::%@@@@@@@      d8888888888 888  888 Y88b.  888  888 888 888  888      X88
  @=::::=%@@@@@@@@      d88P     888 888  888  "Y888 888  888 888 "Y888888  88888P'
     @@@@@@@@@@
                   
                   Orange Pi Zero 3 Edition
EOF
)

# Функція для створення файлів-заглушок для Raspberry Pi
function create_raspberry_pi_stubs() {
    echo "Створення файлів-заглушок для сумісності з Raspberry Pi..."
    
    # Створюємо директорію device-tree якщо її немає
    sudo mkdir -p /proc/device-tree
    
    # Створюємо файл model якщо його немає
    if [ ! -f /proc/device-tree/model ]; then
        # Створюємо тимчасовий файл model для Orange Pi
        echo "Orange Pi Zero3" | sudo tee /proc/device-tree/model > /dev/null
    fi
    
    # Створюємо інші потрібні файли для Raspberry Pi сумісності
    sudo mkdir -p /opt/vc/bin
    sudo mkdir -p /boot/firmware
    
    # Створюємо заглушки для RPi утиліт
    if [ ! -f /opt/vc/bin/vcgencmd ]; then
        cat << 'EOF' | sudo tee /opt/vc/bin/vcgencmd > /dev/null
#!/bin/bash
# Заглушка vcgencmd для Orange Pi
case "$1" in
    "measure_temp")
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            temp=$(cat /sys/class/thermal/thermal_zone0/temp)
            temp_c=$((temp / 1000))
            echo "temp=${temp_c}.0'C"
        else
            echo "temp=45.0'C"
        fi
        ;;
    "get_mem"*)
        echo "256M"
        ;;
    *)
        echo "Команда не підтримується на Orange Pi"
        ;;
esac
EOF
        sudo chmod +x /opt/vc/bin/vcgencmd
    fi
    
    # Створюємо config.txt якщо його немає
    if [ ! -f /boot/firmware/config.txt ]; then
        sudo touch /boot/firmware/config.txt
    fi
    
    # Створюємо cmdline.txt якщо його немає
    if [ ! -f /boot/firmware/cmdline.txt ]; then
        cat /proc/cmdline | sudo tee /boot/firmware/cmdline.txt > /dev/null
    fi
}

# Install gum from Charm.sh.
# Gum helps you write shell scripts more efficiently.
function install_prerequisites() {
    if [ -f /usr/bin/gum ] && [ -f /usr/bin/jq ]; then
        return
    fi

    sudo apt -y update && sudo apt -y install gnupg

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | \
        sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        | sudo tee /etc/apt/sources.list.d/charm.list

    sudo apt -y update && sudo apt -y install gum jq
}

function display_banner() {
    local TITLE="${1:-Anthias Installer}"
    local COLOR="212"

    gum style \
        --foreground "${COLOR}" \
        --border-foreground "${COLOR}" \
        --border "thick" \
        --margin "1 1" \
        --padding "2 6" \
        "${TITLE}"
}

function display_section() {
    local TITLE="${1:-Section}"
    local COLOR="#00FFFF"

    gum style \
        --foreground "${COLOR}" \
        --border-foreground "${COLOR}" \
        --border "thick" \
        --align center \
        --width 95 \
        --margin "1 1" \
        --padding "1 4" \
        "${TITLE}"
}

function initialize_ansible() {
    sudo mkdir -p /etc/ansible
    echo -e "[local]\nlocalhost ansible_connection=local" | \
        sudo tee /etc/ansible/hosts > /dev/null
}

function initialize_locales() {
    display_section "Ініціалізація локалей"

    if [ ! -f /etc/locale.gen ]; then
        # No locales found. Creating locales with default UK/US setup.
        echo -e "en_GB.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\nuk_UA.UTF-8 UTF-8" | \
            sudo tee /etc/locale.gen > /dev/null
        sudo locale-gen
    fi
}

function install_packages() {
    display_section "Встановлення пакетів через APT"

    local APT_INSTALL_ARGS=(
        "git"
        "libffi-dev"
        "libssl-dev"
        "whois"
        "lsb-release"
    )

    if [ "$DISTRO_VERSION" -ge 12 ]; then
        APT_INSTALL_ARGS+=(
            "python3-dev"
            "python3-full"
        )
    else
        APT_INSTALL_ARGS+=(
            "python3"
            "python3-dev"
            "python3-pip"
            "python3-venv"
        )
    fi

    if [ "$MANAGE_NETWORK" = "Yes" ]; then
        APT_INSTALL_ARGS+=("network-manager")
    fi

    # Для Orange Pi не змінюємо джерела APT
    # Коментуємо рядок який змінює sources.list для не-x86_64
    # if [ "$ARCHITECTURE" != "x86_64" ]; then
    #     sudo sed -i 's/apt.screenlyapp.com/archive.raspbian.org/g' \
    #         /etc/apt/sources.list
    # fi

    sudo apt update -y
    sudo apt-get install -y "${APT_INSTALL_ARGS[@]}"
}

function install_ansible() {
    display_section "Встановлення Ansible"

    REQUIREMENTS_URL="$GITHUB_RAW_URL/$BRANCH/requirements/requirements.host.txt"
    if [ "$DISTRO_VERSION" -le 11 ]; then
        ANSIBLE_VERSION="ansible-core==2.15.9"
    else
        ANSIBLE_VERSION=$(curl -s $REQUIREMENTS_URL | grep ansible)
    fi

    SUDO_ARGS=()

    if python3 -c "import venv" &> /dev/null; then
        gum format 'Модуль `venv` виявлено. Активація віртуального середовища...'

        echo

        python3 -m venv /home/${USER}/installer_venv
        source /home/${USER}/installer_venv/bin/activate

        SUDO_ARGS+=("--preserve-env" "env" "PATH=$PATH")
    fi

    # @TODO: Remove me later. Cryptography 38.0.3 won't build at the moment.
    # See https://github.com/Screenly/Anthias/issues/1654 for details.
    sudo ${SUDO_ARGS[@]} pip install cryptography==38.0.1
    sudo ${SUDO_ARGS[@]} pip install "$ANSIBLE_VERSION"
}

function set_device_type() {
    # Модифікована функція для Orange Pi
    if [ ! -f /proc/device-tree/model ] && [ "$(uname -m)" = "x86_64" ]; then
        export DEVICE_TYPE="x86"
    elif [ -f /proc/device-tree/model ]; then
        MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "")
        case "$MODEL" in
            *"Raspberry Pi 5"*|*"Compute Module 5"*)
                export DEVICE_TYPE="pi5"
                ;;
            *"Raspberry Pi 4"*|*"Compute Module 4"*)
                export DEVICE_TYPE="pi4"
                ;;
            *"Raspberry Pi 3"*|*"Compute Module 3"*)
                export DEVICE_TYPE="pi3"
                ;;
            *"Raspberry Pi 2"*)
                export DEVICE_TYPE="pi2"
                ;;
            *"Orange Pi"*|*"Allwinner"*)
                # Orange Pi визначається як Pi3 для сумісності
                export DEVICE_TYPE="pi3"
                echo "Orange Pi виявлено, використовується профіль pi3 для сумісності"
                ;;
            *)
                export DEVICE_TYPE="pi1"
                ;;
        esac
    else
        # Якщо файл model не існує, спробуємо визначити по архітектурі
        case "$ARCHITECTURE" in
            "aarch64")
                export DEVICE_TYPE="pi3"
                echo "ARM64 архітектура, використовується профіль pi3"
                ;;
            "armv7l")
                export DEVICE_TYPE="pi2"
                echo "ARM32 архітектура, використовується профіль pi2"
                ;;
            *)
                export DEVICE_TYPE="pi1"
                ;;
        esac
    fi
    
    echo "Встановлено тип пристрою: $DEVICE_TYPE"
}

function run_ansible_playbook() {
    display_section "Запуск Ansible Playbook для Anthias"
    set_device_type

    sudo -u ${USER} ${SUDO_ARGS[@]} ansible localhost \
        -m git \
        -a "repo=$REPOSITORY dest=${ANTHIAS_REPO_DIR} version=${BRANCH} force=yes"
    cd ${ANTHIAS_REPO_DIR}/ansible

    if [ "$ARCHITECTURE" == "x86_64" ]; then
        if [ ! -f /etc/sudoers.d/010_${USER}-nopasswd ]; then
            ANSIBLE_PLAYBOOK_ARGS+=("--ask-become-pass")
        fi

        ANSIBLE_PLAYBOOK_ARGS+=(
            "--skip-tags" "raspberry-pi"
        )
    else
        # Для Orange Pi пропускаємо RPi-специфічні завдання
        ANSIBLE_PLAYBOOK_ARGS+=(
            "--skip-tags" "raspberry-pi-specific"
        )
    fi

    sudo -E -u ${USER} ${SUDO_ARGS[@]} \
        ansible-playbook site.yml "${ANSIBLE_PLAYBOOK_ARGS[@]}"
}

function upgrade_docker_containers() {
    display_section "Ініціалізація/Оновлення Docker контейнерів"

    wget -q \
        "$GITHUB_RAW_URL/master/bin/upgrade_containers.sh" \
        -O "$UPGRADE_SCRIPT_PATH"

    sudo -u ${USER} \
        DOCKER_TAG="${DOCKER_TAG}" \
        GIT_BRANCH="${BRANCH}" \
        "${UPGRADE_SCRIPT_PATH}"
}

function cleanup() {
    display_section "Очищення невикористаних пакетів та файлів"

    sudo apt-get autoclean
    sudo apt-get clean
    sudo docker system prune -f
    sudo apt autoremove -y
    
    # Plymouth може не бути доступним на Orange Pi
    sudo apt-get install plymouth --reinstall -y 2>/dev/null || echo "Plymouth недоступний, пропускаємо..."
    
    sudo find /usr/share/doc \
        -depth \
        -type f \
        ! -name copyright \
        -delete 2>/dev/null || true
    sudo find /usr/share/doc \
        -empty \
        -delete 2>/dev/null || true
    sudo rm -rf \
        /usr/share/man \
        /usr/share/groff \
        /usr/share/info/* \
        /usr/share/lintian \
        /usr/share/linda /var/cache/man 2>/dev/null || true
    sudo find /usr/share/locale \
        -type f \
        ! -name 'en' \
        ! -name 'de*' \
        ! -name 'es*' \
        ! -name 'ja*' \
        ! -name 'fr*' \
        ! -name 'zh*' \
        ! -name 'uk*' \
        -delete 2>/dev/null || true
    sudo find /usr/share/locale \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name 'en*' \
        ! -name 'de*' \
        ! -name 'es*' \
        ! -name 'ja*' \
        ! -name 'fr*' \
        ! -name 'zh*' \
        ! -name 'uk*' \
        ! -name 'locale.alias' \
        -exec rm -r {} \; 2>/dev/null || true
}

function modify_permissions() {
    sudo chown -R ${USER}:${USER} /home/${USER}

    # Run `sudo` without entering a password.
    if [ ! -f /etc/sudoers.d/010_${USER}-nopasswd ]; then
        echo "${USER} ALL=(ALL) NOPASSWD: ALL" | \
            sudo tee /etc/sudoers.d/010_${USER}-nopasswd > /dev/null
        sudo chmod 0440 /etc/sudoers.d/010_${USER}-nopasswd
    fi
}

function write_anthias_version() {
    cd ${ANTHIAS_REPO_DIR}
    local GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    local GIT_SHORT_HASH=$(git rev-parse --short HEAD)
    local ANTHIAS_VERSION="Anthias Version: ${GIT_BRANCH}@${GIT_SHORT_HASH} (Orange Pi Edition)"

    echo "${ANTHIAS_VERSION}" > ~/version.md
    echo "$(lsb_release -a 2> /dev/null)" >> ~/version.md
    uname -a >> ~/version.md
}

function post_installation() {
    local POST_INSTALL_MESSAGE=()

    display_section "Встановлення завершено"

    if [ -f /var/run/reboot-required ]; then
        POST_INSTALL_MESSAGE+=(
            "Будь ласка, перезавантажтесь і запустіть \`${UPGRADE_SCRIPT_PATH}\` "
            "щоб завершити встановлення."
        )
    else
        POST_INSTALL_MESSAGE+=(
            "Вам потрібно перезавантажити систему для завершення встановлення."
        )
    fi

    echo

    gum style --foreground "#00FFFF" "${POST_INSTALL_MESSAGE[@]}" | gum format

    echo
    
    echo "ВАЖЛИВО: Після перезавантаження перевірте статус служб:"
    echo "sudo docker ps"
    echo "sudo systemctl status anthias"
    echo ""

    gum confirm "Чи хочете ви перезавантажити зараз?" && \
        gum style --foreground "#FF00FF" "Перезавантаження..." | gum format && \
        sudo reboot
}

function set_custom_version() {
    BRANCH=$(
        gum input \
            --header "Введіть назву тегу, який ви хочете встановити" \
    )

    local STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${GITHUB_API_REPO_URL}/git/refs/tags/$BRANCH")

    if [ "$STATUS_CODE" -ne 200 ]; then
        gum style "Неправильна назва тегу." \
            | gum format
        echo
        exit 1
    fi

    local DOCKER_TAG_FILE_URL="${GITHUB_RELEASES_URL}/download/${BRANCH}/docker-tag"
    STATUS_CODE=$(curl -sL -o /dev/null -w "%{http_code}" \
        "$DOCKER_TAG_FILE_URL")

    if [ "$STATUS_CODE" -ne 200 ]; then
        gum style "Ця версія не має файлу \`docker-tag\`." \
            | gum format
        echo
        exit 1
    fi

    DOCKER_TAG=$(curl -sL "$DOCKER_TAG_FILE_URL")
}

function check_system_compatibility() {
    display_section "Перевірка сумісності системи"
    
    detect_device_info
    
    # Перевірка архітектури
    case "$ARCHITECTURE" in
        "aarch64"|"armv7l")
            echo "Архітектура $ARCHITECTURE підтримується ✓"
            ;;
        "x86_64")
            echo "Архітектура x86_64 підтримується ✓"
            ;;
        *)
            echo "Попередження: Архітектура $ARCHITECTURE може бути не повністю підтримана"
            gum confirm "Продовжити все одно?" || exit 0
            ;;
    esac
    
    # Перевірка SoC та рекомендації
    case "$DEVICE_VENDOR" in
        "amlogic")
            echo "Amlogic SoC виявлено: $DEVICE_SOC"
            case "$DEVICE_SOC" in
                *"S905X3"*|*"S922X"*|*"A311D"*)
                    echo "Потужний SoC - рекомендується для 1080p контенту ✓"
                    ;;
                *)
                    echo "Помірний SoC - рекомендується легкий контент"
                    ;;
            esac
            ;;
        "orangepi"|"allwinner")
            echo "Allwinner SoC виявлено: $DEVICE_SOC"
            echo "Рекомендується контент до 1080p"
            ;;
        "rockchip")
            echo "Rockchip SoC виявлено"
            echo "Гарна підтримка відео кодеків ✓"
            ;;
        *)
            echo "Загальний ARM SBC пристрій"
            ;;
    esac
    
    # Перевірка наявності Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker не встановлено. Він буде встановлений під час процесу."
    fi
    
    # Перевірка доступної пам'яті
    MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEMORY_MB=$((MEMORY_KB / 1024))
    
    if [ $MEMORY_MB -lt 700 ]; then
        echo "⚠️  Попередження: Доступно лише ${MEMORY_MB}MB RAM"
        echo "Для стабільної роботи рекомендується принаймні 1GB"
        echo "Буде створено swap файл для компенсації"
        gum confirm "Продовжити все одно?" || exit 0
    elif [ $MEMORY_MB -lt 1500 ]; then
        echo "Пам'ять: ${MEMORY_MB}MB - достатньо для базових функцій"
        echo "Рекомендується легкий контент (зображення, простий HTML)"
    else
        echo "Пам'ять: ${MEMORY_MB}MB - відмінно для мультимедіа контенту ✓"
    fi
    
    # Перевірка дискового простору
    DISK_AVAILABLE=$(df / | tail -1 | awk '{print $4}')
    DISK_AVAILABLE_GB=$((DISK_AVAILABLE / 1024 / 1024))
    
    if [ $DISK_AVAILABLE_GB -lt 3 ]; then
        echo "⚠️  Попередження: Доступно лише ${DISK_AVAILABLE_GB}GB дискового простору"
        echo "Рекомендується принаймні 8GB вільного місця"
        gum confirm "Продовжити все одно?" || exit 0
    else
        echo "Дисковий простір: ${DISK_AVAILABLE_GB}GB - OK ✓"
    fi
    
    # Перевірка мережі
    if ping -c 1 -W 3 google.com >/dev/null 2>&1; then
        echo "Інтернет з'єднання: OK ✓"
    else
        echo "⚠️  Проблема з інтернет з'єднанням"
        echo "Перевірте мережеві налаштування"
        gum confirm "Спробувати продовжити?" || exit 0
    fi
}

function main() {
    # Перевірка сумісності перед початком
    check_system_compatibility
    
    # Створення заглушок для сумісності з Raspberry Pi
    create_raspberry_pi_stubs
    
    install_prerequisites && clear

    display_banner "${TITLE_TEXT}"

    gum format "${INTRO_MESSAGE[@]}"
    echo
    gum confirm "Чи все ще хочете продовжити?" || exit 0
    gum confirm "${MANAGE_NETWORK_PROMPT[@]}" && \
        export MANAGE_NETWORK="Yes" || \
        export MANAGE_NETWORK="No"

    VERSION=$(
        gum choose \
            --header "${VERSION_PROMPT}" \
            -- "${VERSION_PROMPT_CHOICES[@]}"
    )

    if [ "$VERSION" == "latest" ]; then
        BRANCH="master"
    else
        set_custom_version
    fi

    gum confirm "${SYSTEM_UPGRADE_PROMPT[@]}" && {
        SYSTEM_UPGRADE="Yes"
    } || {
        SYSTEM_UPGRADE="No"
        ANSIBLE_PLAYBOOK_ARGS+=("--skip-tags" "system-upgrade")
    }

    display_section "Підсумок користувацького вводу"
    gum format "**Керування мережею:**     ${MANAGE_NETWORK}"
    gum format "**Гілка/Тег:**             \`${BRANCH}\`"
    gum format "**Оновлення системи:**     ${SYSTEM_UPGRADE}"
    gum format "**Префікс Docker тегу:**   \`${DOCKER_TAG}\`"
    gum format "**Архітектура:**           \`${ARCHITECTURE}\`"
    gum format "**Тип пристрою:**          \`${DEVICE_TYPE:-автовизначення}\`"

    if [ ! -d "${ANTHIAS_REPO_DIR}" ]; then
        mkdir "${ANTHIAS_REPO_DIR}"
    fi

    initialize_ansible
    initialize_locales
    install_packages
    install_ansible
    run_ansible_playbook

    upgrade_docker_containers
    cleanup
    modify_permissions

    write_anthias_version
    post_installation
}

# Перевірка що скрипт запущено з правильними правами
if [ "$EUID" -eq 0 ]; then
    echo "Не запускайте цей скрипт з правами root. Використовуйте звичайного користувача."
    echo "Скрипт сам запитає sudo коли потрібно."
    exit 1
fi

main
