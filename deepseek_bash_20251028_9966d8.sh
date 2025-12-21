#!/bin/bash

# Pterodactyl Node & Wings Auto Installer
# Robust Version - Anti Error
# Created for Blademoon

echo "================================================"
echo "  Pterodactyl Node Auto Installer - No Error"
echo "================================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Get inputs with validation
while true; do
    read -p "Enter Panel URL (e.g., https://blademoon.my.id): " PANEL_URL
    if [[ $PANEL_URL =~ ^https?:// ]]; then
        break
    else
        log_error "Invalid URL format. Must start with http:// or https://"
    fi
done

while true; do
    read -p "Enter Node ID: " NODE_ID
    if [[ $NODE_ID =~ ^[0-9]+$ ]]; then
        break
    else
        log_error "Node ID must be a number"
    fi
done

while true; do
    read -p "Enter Configuration Token: " CONFIG_TOKEN
    if [[ ! -z $CONFIG_TOKEN ]]; then
        break
    else
        log_error "Token cannot be empty"
    fi
done

read -p "Enter Node FQDN/IP [$(hostname -f)]: " NODE_FQDN
NODE_FQDN=${NODE_FQDN:-$(hostname -f)}

# Installation starts
log_info "Starting installation process..."

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        log_success "$1"
    else
        log_error "$2"
        exit 1
    fi
}

# Update system
log_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt update -q
apt upgrade -y -q
check_success "System updated" "System update failed"

# Install dependencies
log_info "Installing dependencies..."
apt install -y -q curl wget gnupg software-properties-common apt-transport-https ca-certificates
check_success "Dependencies installed" "Dependencies installation failed"

# Install Docker
log_info "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    check_success "Docker installed" "Docker installation failed"
else
    log_success "Docker already installed"
fi

# Start and enable Docker
systemctl enable docker --now
check_success "Docker service started" "Docker service failed"

# Install Wings
log_info "Installing Wings..."
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) log_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Download wings
WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"
curl -L -o /usr/local/bin/wings $WINGS_URL
chmod +x /usr/local/bin/wings
check_success "Wings downloaded" "Wings download failed"

# Configure wings with retry logic
log_info "Configuring Wings (this may take a moment)..."
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    log_info "Configuration attempt $((RETRY_COUNT+1))..."
    
    # Test panel connectivity first
    if curl -s --head --request GET "$PANEL_URL" | grep "200 OK" > /dev/null; then
        log_success "Panel is accessible"
    else
        log_warning "Cannot verify panel accessibility, continuing anyway..."
    fi
    
    # Run wings configure
    wings configure --panel-url "$PANEL_URL" --token "$CONFIG_TOKEN" --node "$NODE_ID"
    
    if [ $? -eq 0 ]; then
        log_success "Wings configured successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            log_error "Wings configuration failed after $MAX_RETRIES attempts"
            log_info "Please check:"
            log_info "1. Token is fresh (generated within 5 minutes)"
            log_info "2. Panel URL is correct"
            log_info "3. Node ID is correct"
            log_info "4. Network connectivity"
            exit 1
        else
            log_warning "Configuration failed, retrying in 5 seconds..."
            sleep 5
        fi
    fi
done

# Create systemd service for wings
log_info "Creating Wings service..."
cat > /etc/systemd/system/wings.service << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start wings
systemctl daemon-reload
systemctl enable wings
systemctl start wings

# Wait and check status
sleep 10

if systemctl is-active --quiet wings; then
    log_success "Wings is running successfully!"
else
    log_error "Wings failed to start"
    log_info "Checking logs..."
    journalctl -u wings --no-pager -n 20
    exit 1
fi

# Configure firewall if ufw exists
log_info "Configuring firewall..."
if command -v ufw > /dev/null; then
    ufw allow 22/tcp comment 'SSH'
    ufw allow 8080/tcp comment 'Wings Communication'
    ufw allow 2022/tcp comment 'SFTP'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    echo "y" | ufw enable
    log_success "Firewall configured"
else
    log_warning "UFW not available, configure firewall manually if needed"
fi

# Final verification
log_info "Performing final verification..."

# Check services
DOCKER_STATUS=$(systemctl is-active docker)
WINGS_STATUS=$(systemctl is-active wings)

echo ""
echo "================================================"
echo "           INSTALLATION COMPLETE!"
echo "================================================"
echo -e "Docker Status: ${GREEN}$DOCKER_STATUS${NC}"
echo -e "Wings Status:  ${GREEN}$WINGS_STATUS${NC}"
echo ""
echo -e "Node should be ${GREEN}ONLINE${NC} in your panel:"
echo -e "Panel URL: $PANEL_URL/admin/nodes"
echo ""
echo "Allocated Ports:"
echo "- Wings Communication: 8080"
echo "- SFTP: 2022" 
echo "- Game Servers: 25565-25575 (example range)"
echo ""
echo "Troubleshooting commands:"
echo "Check wings logs: journalctl -u wings -f"
echo "Check wings status: systemctl status wings"
echo "Test connectivity: curl $PANEL_URL/api/"
echo "================================================"

log_success "Node installation completed! Check your panel - should be GREEN! 🟢"