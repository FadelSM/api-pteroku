#!/bin/bash

# =============================================
# PHP-FPM FIX SCRIPT
# Fix www-data user error and PHP-FPM startup
# =============================================

echo "========================================"
echo "        PHP-FPM FIX SCRIPT"
echo "   Fixing www-data user and PHP-FPM"
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

# ==================== STOP PHP-FPM FIRST ====================
log_info "Stopping PHP-FPM services..."
systemctl stop php8.3-fpm php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm 2>/dev/null

# ==================== FIX WWW-DATA USER ====================
log_info "Fixing www-data user..."

# Check if www-data user exists
if ! id "www-data" &>/dev/null; then
    log_warn "www-data user not found, creating..."
    useradd -r -s /bin/false -d /var/www -U www-data
    log_success "www-data user created"
else
    log_info "www-data user already exists"
fi

# Check if www-data group exists
if ! getent group www-data > /dev/null; then
    log_warn "www-data group not found, creating..."
    groupadd www-data
    usermod -a -G www-data www-data
    log_success "www-data group created"
fi

# ==================== CREATE REQUIRED DIRECTORIES ====================
log_info "Creating required directories..."

mkdir -p /var/www
mkdir -p /run/php
mkdir -p /var/lib/php/sessions
mkdir -p /var/log/php

# Set permissions
chown -R www-data:www-data /var/www /run/php /var/lib/php/sessions
chmod 755 /var/www /run/php /var/lib/php/sessions

log_success "Directories created and permissions set"

# ==================== FIX PHP-FPM CONFIGURATION ====================
log_info "Fixing PHP-FPM configuration..."

# Fix for PHP 8.3
if [ -d "/etc/php/8.3" ]; then
    log_info "Configuring PHP 8.3 FPM..."
    
    # Create pool config
    cat > /etc/php/8.3/fpm/pool.d/www.conf << 'EOF'
[www]
user = www-data
group = www-data
listen = /run/php/php8.3-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
catch_workers_output = yes
security.limit_extensions = .php .php3 .php4 .php5 .php7
php_admin_value[display_errors] = Off
php_admin_flag[log_errors] = on
php_value[session.save_handler] = files
php_value[session.save_path]    = /var/lib/php/sessions
php_value[soap.wsdl_cache_dir]  = /var/lib/php/wsdlcache
EOF

    log_success "PHP 8.3 FPM configured"
fi

# Fix for PHP 8.2
if [ -d "/etc/php/8.2" ]; then
    log_info "Configuring PHP 8.2 FPM..."
    
    cat > /etc/php/8.2/fpm/pool.d/www.conf << 'EOF'
[www]
user = www-data
group = www-data
listen = /run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
EOF

    log_success "PHP 8.2 FPM configured"
fi

# Fix for PHP 8.1
if [ -d "/etc/php/8.1" ]; then
    log_info "Configuring PHP 8.1 FPM..."
    
    cat > /etc/php/8.1/fpm/pool.d/www.conf << 'EOF'
[www]
user = www-data
group = www-data
listen = /run/php/php8.1-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
EOF

    log_success "PHP 8.1 FPM configured"
fi

# ==================== FIX PHP.INI CONFIGURATION ====================
log_info "Fixing PHP configuration..."

# Fix PHP 8.3 php.ini
if [ -f "/etc/php/8.3/fpm/php.ini" ]; then
    sed -i 's/^;error_log =.*/error_log = \/var\/log\/php\/php8.3-fpm.log/' /etc/php/8.3/fpm/php.ini
    sed -i 's/^upload_max_filesize =.*/upload_max_filesize = 100M/' /etc/php/8.3/fpm/php.ini
    sed -i 's/^post_max_size =.*/post_max_size = 100M/' /etc/php/8.3/fpm/php.ini
    sed -i 's/^memory_limit =.*/memory_limit = 256M/' /etc/php/8.3/fpm/php.ini
fi

# Fix PHP 8.2 php.ini
if [ -f "/etc/php/8.2/fpm/php.ini" ]; then
    sed -i 's/^;error_log =.*/error_log = \/var\/log\/php\/php8.2-fpm.log/' /etc/php/8.2/fpm/php.ini
    sed -i 's/^upload_max_filesize =.*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
    sed -i 's/^post_max_size =.*/post_max_size = 100M/' /etc/php/8.2/fpm/php.ini
fi

# ==================== CLEAN UP OLD SOCKETS ====================
log_info "Cleaning up old sockets..."
rm -f /run/php/php*.sock
rm -f /var/run/php/php*.sock

# ==================== START PHP-FPM SERVICES ====================
log_info "Starting PHP-FPM services..."

# Start appropriate PHP version
if [ -d "/etc/php/8.3" ]; then
    systemctl enable php8.3-fpm
    systemctl start php8.3-fpm
    log_info "PHP 8.3 FPM started"
elif [ -d "/etc/php/8.2" ]; then
    systemctl enable php8.2-fpm
    systemctl start php8.2-fpm
    log_info "PHP 8.2 FPM started"
elif [ -d "/etc/php/8.1" ]; then
    systemctl enable php8.1-fpm
    systemctl start php8.1-fpm
    log_info "PHP 8.1 FPM started"
fi

# ==================== VERIFY FIX ====================
log_info "Verifying fix..."

# Check services
echo ""
echo "=== SERVICE STATUS ==="
systemctl status php8.3-fpm --no-pager -l 2>/dev/null || echo "PHP 8.3 FPM not installed"
systemctl status php8.2-fpm --no-pager -l 2>/dev/null || echo "PHP 8.2 FPM not installed"
systemctl status php8.1-fpm --no-pager -l 2>/dev/null || echo "PHP 8.1 FPM not installed"

# Check sockets
echo ""
echo "=== SOCKETS ==="
ls -la /run/php/ 2>/dev/null || echo "No sockets found"

# Check www-data user
echo ""
echo "=== USER VERIFICATION ==="
id www-data
groups www-data

# Test PHP
echo ""
echo "=== PHP VERSION ==="
php -v 2>/dev/null || echo "PHP CLI not available"

# ==================== COMPLETION ====================
echo ""
echo "========================================"
log_info "PHP-FPM FIX COMPLETED!"
echo "========================================"
echo ""
echo "If services are still failing, check:"
echo "1. journalctl -u php8.3-fpm -f"
echo "2. Check /var/log/php/ for error logs"
echo "3. Verify nginx/Apache configuration"
echo ""
echo "Now you can retry Pterodactyl installation!"