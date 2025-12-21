#!/bin/bash

# Auto Install Pterodactyl Node + Wings
# Created by Blademoon

echo "======================================="
echo "  Pterodactyl Node Auto Installer"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Get user input
echo ""
read -p "Enter Panel URL (e.g., https://blademoon.my.id): " PANEL_URL
read -p "Enter Node ID (from panel): " NODE_ID
read -p "Enter Configuration Token (from panel): " CONFIG_TOKEN
read -p "Enter Node FQDN/IP: " NODE_FQDN

# Validate inputs
if [ -z "$PANEL_URL" ] || [ -z "$NODE_ID" ] || [ -z "$CONFIG_TOKEN" ] || [ -z "$NODE_FQDN" ]; then
    print_error "All fields are required!"
    exit 1
fi

print_status "Starting installation..."

# Update system
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install dependencies
print_status "Installing dependencies..."
apt install -y curl software-properties-common apt-transport-https ca-certificates gnupg

# Install Docker
print_status "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Download and install Wings
print_status "Installing Wings..."
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl

# Download wings binary
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"
chmod u+x /usr/local/bin/wings

# Configure wings
print_status "Configuring Wings..."
wings configure --panel-url "$PANEL_URL" --token "$CONFIG_TOKEN" --node "$NODE_ID"

if [ $? -ne 0 ]; then
    print_error "Configuration failed! Please check your token and try again."
    exit 1
fi

# Create wings service
print_status "Creating systemd service..."
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

# Wait for wings to start
sleep 5

# Check wings status
if systemctl is-active --quiet wings; then
    print_status "Wings is running successfully!"
else
    print_error "Wings failed to start. Check logs: journalctl -u wings"
    exit 1
fi

# Configure firewall
print_status "Configuring firewall..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp
    ufw allow 8080/tcp
    ufw allow 2022/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    print_status "Firewall configured"
else
    print_warning "UFW not found, please configure firewall manually"
fi

# Verify installation
print_status "Verifying installation..."
echo ""
echo "=== Verification Steps ==="
echo "1. Wings Status: $(systemctl is-active wings)"
echo "2. Docker Status: $(systemctl is-active docker)"
echo "3. Listening Ports:"
netstat -tulpn | grep -E ':(8080|2022)'

# Final instructions
echo ""
echo "======================================="
echo "  INSTALLATION COMPLETE!"
echo "======================================="
echo -e "${GREEN}✓ Node should be ONLINE in your panel${NC}"
echo ""
echo "Next steps:"
echo "1. Check panel: $PANEL_URL/nodes"
echo "2. Node should be GREEN (online)"
echo "3. Create allocations for servers"
echo ""
echo "Troubleshooting:"
echo "- Check wings logs: journalctl -u wings -f"
echo "- Verify token was valid (expires in 5min)"
echo "- Check firewall rules"
echo ""

print_status "Node installation completed successfully!"