#!/bin/bash

# System setup for Orange Pi Zero 3 for Anthias
set -e

echo "=== System Setup for Orange Pi Zero 3 ==="

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y \
    docker.io \
    docker-compose \
    curl \
    wget \
    jq \
    mesa-utils \
    libgles2-mesa \
    libegl1-mesa \
    libdrm2 \
    xserver-xorg \
    xinit

# Enable Docker on boot
sudo systemctl enable docker
sudo systemctl start docker

# Configure graphics for Orange Pi
echo "Configuring graphics..."

# Create Xorg configuration
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-orange-pi.conf > /dev/null << 'EOF'
Section "Device"
    Identifier "OrangePi"
    Driver "modesetting"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "OrangePi"
EndSection
EOF

# Set up environment variables
echo "export DISPLAY=:0" >> ~/.bashrc
echo "export XDG_RUNTIME_DIR=/tmp" >> ~/.bashrc
echo "export PULSE_SERVER=unix:/run/pulse/native" >> ~/.bashrc

source ~/.bashrc

# Add user to required groups
sudo usermod -aG docker $USER
sudo usermod -aG video $USER
sudo usermod -aG render $USER

echo "=== System setup complete! ==="
echo "Please reboot your system: sudo reboot"