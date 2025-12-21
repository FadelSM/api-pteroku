#!/bin/bash

# =============================================
# NGINX FIX SCRIPT
# Fix missing nginx.conf and configuration
# =============================================

echo "========================================"
echo "        NGINX FIX SCRIPT"
echo "   Fixing missing nginx.conf"
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

# ==================== STOP NGINX ====================
log_info "Stopping nginx..."
systemctl stop nginx 2>/dev/null
pkill nginx 2>/dev/null

# ==================== REINSTALL NGINX ====================
log_info "Reinstalling nginx..."
apt remove --purge -y nginx nginx-common nginx-full
apt autoremove -y

# Install nginx fresh
apt update
apt install -y nginx

# ==================== VERIFY NGINX FILES ====================
log_info "Verifying nginx files..."

# Check if nginx.conf exists
if [ ! -f "/etc/nginx/nginx.conf" ]; then
    log_warn "nginx.conf missing, creating default..."
    
    # Create default nginx.conf
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    log_success "nginx.conf created"
fi

# Create required directories
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /var/log/nginx
mkdir -p /var/www/html

# Create default site
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# Enable default site
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# Create test index.html
echo "<html><body><h1>Nginx is working!</h1></body></html>" > /var/www/html/index.html

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# ==================== TEST NGINX CONFIGURATION ====================
log_info "Testing nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    log_success "Nginx configuration test passed"
else
    log_error "Nginx configuration test failed"
    log_info "Checking for errors..."
    nginx -t 2>&1
    exit 1
fi

# ==================== START NGINX ====================
log_info "Starting nginx..."
systemctl enable nginx
systemctl start nginx

# Check status
if systemctl is-active --quiet nginx; then
    log_success "Nginx is running successfully!"
else
    log_error "Nginx failed to start"
    log_info "Checking logs..."
    journalctl -u nginx --no-pager -n 10
    exit 1
fi

# ==================== VERIFICATION ====================
log_info "Verifying nginx..."

echo ""
echo "=== NGINX STATUS ==="
systemctl status nginx --no-pager -l

echo ""
echo "=== LISTENING PORTS ==="
netstat -tulpn | grep nginx

echo ""
echo "=== TESTING HTTP ==="
curl -I http://localhost

# ==================== COMPLETION ====================
echo ""
echo "========================================"
log_info "NGINX FIX COMPLETED!"
echo "========================================"
echo ""
echo "Nginx should now be working properly."
echo "You can access your server via: http://your-server-ip"
echo ""
echo "Next: Fix PHP-FPM if needed, then install Pterodactyl"