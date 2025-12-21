#!/bin/bash

# =============================================
# VPS TOTAL CLEAN SCRIPT - BACK TO FRESH STATE
# =============================================

echo "========================================"
echo "    VPS TOTAL CLEANUP SCRIPT"
echo "    WARNING: THIS WILL DELETE EVERYTHING!"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root: sudo bash $0"
    exit 1
fi

# Final warning
echo ""
log_warn "THIS SCRIPT WILL:"
echo "  - Remove ALL Docker containers, images, volumes"
echo "  - Remove Pterodactyl Panel & Wings"
echo "  - Remove MySQL/MariaDB"
echo "  - Remove Nginx/Apache"
echo "  - Remove PHP, Composer, Node.js"
echo "  - Clean ALL temporary files"
echo "  - Remove ALL custom services"
echo ""
read -p "Are you sure? (type 'YES' to continue): " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    log_error "Cancelled by user"
    exit 1
fi

# ==================== STOP ALL SERVICES ====================
log_info "Stopping all services..."

# Stop Pterodactyl services
systemctl stop pteroq wings panel 2>/dev/null

# Stop web servers
systemctl stop nginx apache2 2>/dev/null

# Stop database
systemctl stop mysql mariadb 2>/dev/null

# Stop Docker
systemctl stop docker 2>/dev/null

# Disable services
systemctl disable pteroq wings panel nginx apache2 mysql mariadb 2>/dev/null

# ==================== DOCKER CLEANUP ====================
log_info "Cleaning Docker..."

# Remove all containers
docker rm -f $(docker ps -aq) 2>/dev/null

# Remove all images
docker rmi -f $(docker images -q) 2>/dev/null

# Remove all volumes
docker volume rm $(docker volume ls -q) 2>/dev/null

# Remove all networks
docker network rm $(docker network ls -q) 2>/dev/null

# Clean system
docker system prune -a -f --volumes

# ==================== PTERODACTYL CLEANUP ====================
log_info "Removing Pterodactyl..."

# Remove panel files
rm -rf /var/www/pterodactyl
rm -rf /var/www/panel

# Remove wings
rm -rf /etc/pterodactyl
rm -f /usr/local/bin/wings
rm -rf /srv/daemon-data
rm -rf /var/lib/pterodactyl

# Remove service files
rm -f /etc/systemd/system/pteroq.service
rm -f /etc/systemd/system/wings.service
rm -f /etc/systemd/system/panel.service

# ==================== DATABASE CLEANUP ====================
log_info "Cleaning database..."

# Remove MySQL/MariaDB
apt remove --purge -y mysql-server mysql-client mariadb-server mariadb-client
rm -rf /var/lib/mysql
rm -rf /etc/mysql

# ==================== WEB SERVER CLEANUP ====================
log_info "Removing web servers..."

# Remove Nginx
apt remove --purge -y nginx nginx-common
rm -rf /etc/nginx
rm -rf /var/www/html
rm -rf /var/log/nginx

# Remove Apache
apt remove --purge -y apache2 apache2-utils
rm -rf /etc/apache2
rm -rf /var/www/html

# ==================== APPLICATION CLEANUP ====================
log_info "Removing applications..."

# Remove PHP
apt remove --purge -y php* php-*
rm -rf /etc/php

# Remove Composer
rm -f /usr/local/bin/composer
rm -rf ~/.composer

# Remove Node.js
apt remove --purge -y nodejs npm
rm -rf /usr/lib/node_modules
rm -rf ~/.npm
rm -rf ~/.node-gyp

# Remove Redis
apt remove --purge -y redis-server
rm -rf /var/lib/redis

# ==================== USER CLEANUP ====================
log_info "Cleaning users..."

# Remove pterodactyl user
userdel -r pterodactyl 2>/dev/null

# Remove www-data user (will be recreated if needed)
userdel -r www-data 2>/dev/null

# ==================== FILE CLEANUP ====================
log_info "Cleaning files and logs..."

# Clean logs
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean cache
apt clean
apt autoremove -y

# Clean home directory
rm -rf ~/.bash_history
rm -rf ~/.ssh/known_hosts
rm -rf ~/.cache

# Clean system
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*

# ==================== SERVICE CLEANUP ====================
log_info "Cleaning services..."

# Reset systemd
systemctl daemon-reload
systemctl reset-failed

# Remove custom services
find /etc/systemd/system -name "*.service" -type f ! -name "*.wants" -exec rm -f {} \;

# ==================== FIREWALL RESET ====================
log_info "Resetting firewall..."

# Reset UFW
ufw --force reset
ufw --force disable

# Reset iptables
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# ==================== FINAL CLEANUP ====================
log_info "Final cleanup..."

# Update package list
apt update

# Clean package cache
apt autoclean
apt autoremove -y

# Remove orphaned packages
deborphan | xargs apt remove -y

# Clean history
history -c
history -w

# ==================== COMPLETE ====================
echo ""
echo "========================================"
log_info "VPS CLEANUP COMPLETED!"
echo "========================================"
echo ""
echo "Your VPS is now FRESH like new!"
echo ""
echo "Recommended next steps:"
echo "1. reboot"
echo "2. Install fresh system if needed"
echo ""
read -p "Reboot now? (y/n): " REBOOT_NOW

if [ "$REBOOT_NOW" = "y" ] || [ "$REBOOT_NOW" = "Y" ]; then
    log_info "Rebooting system..."
    reboot
else
    log_info "Please reboot manually: sudo reboot"
fi