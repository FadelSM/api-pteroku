#!/bin/bash
# ==========================================================
# SUPER DDoS SHIELD – INSTALLER
# Compatible: Debian 11/12, Ubuntu 20/22, CentOS 8/9, Alma/Rocky 8+
# Idempotent → safe to run multiple times
# ==========================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "❗ Run as root"; exit 1; }

echo "🔥 SUPER DDoS SHIELD – INSTALLER"

# ----------------------------------------------------------
# 0. OS DETECT + PACKAGE MANAGER
# ----------------------------------------------------------
if command -v apt-get &>/dev/null; then
    PKG="apt"; INSTALL="apt-get install -y"
elif command -v dnf &>/dev/null; then
    PKG="dnf"; INSTALL="dnf install -y"
elif command -v yum &>/dev/null; then
    PKG="yum"; INSTALL="yum install -y"
else
    echo "❌ Unsupported distro"; exit 1
fi

# ----------------------------------------------------------
# 1. DEPENDENCIES (auto-fix m4/bison/flex/elf/clang)
# ----------------------------------------------------------
echo "📦 Installing build deps..."
$INSTALL git curl gcc make clang llvm libelf-devel libconfig-devel \
         m4 bison flex ipset iptables fail2ban python3 python3-pip \
         linux-tools-$(uname -r) elfutils-libelf-devel || true

# Ubuntu/Debian specific
if [[ $PKG == "apt" ]]; then
    $INSTALL libbpf-dev linux-headers-$(uname -r) || true
fi

# ----------------------------------------------------------
# 2. BACKUP ORIGINAL IPTABLES
# ----------------------------------------------------------
BACKUP_DIR="/root/iptables-backup-$(date +%F)"
mkdir -p "$BACKUP_DIR"
iptables-save > "$BACKUP_DIR/iptables-original.rules"
echo "💾 Original iptables saved to $BACKUP_DIR"

# ----------------------------------------------------------
# 3. CLONE & BUILD XDP-FIREWALL (gamemann – maintained)
# ----------------------------------------------------------
XDP_DIR="/opt/XDP-Firewall"
[[ -d "$XDP_DIR" ]] && { echo "⚠️  XDP-Firewall already cloned – pulling latest"; git -C "$XDP_DIR" pull --recurse; } || \
    git clone --recursive https://github.com/gamemann/XDP-Firewall.git "$XDP_DIR"
cd "$XDP_DIR"

# configure & build xdp-tools submodule jika belum
if [[ ! -f modules/xdp-tools/config.mk ]]; then
    echo "🔨 Configuring xdp-tools submodule..."
    (cd modules/xdp-tools && ./configure)
fi
make clean && make -j$(nproc)
make install
echo "✅ XDP-Firewall built & installed"

# ----------------------------------------------------------
# 4. CONFIG FILE
# ----------------------------------------------------------
CONFIG="/etc/xdp-firewall.conf"
cat > "$CONFIG" <<'EOF'
# SUPER DDoS SHIELD – XDP CONFIG
interfaces = ["auto"]          # auto-detect default iface
ports      = [80,443,8080,25565]
rate_limit = 100               # pkts/sec
rate_limit_window = 1
block_time = 60                # seconds
log_level  = 2
EOF

# ----------------------------------------------------------
# 5. SYSTEMD SERVICE (idempotent)
# ----------------------------------------------------------
SERVICE="/etc/systemd/system/xdp-firewall.service"
cat > "$SERVICE" <<'EOF'
[Unit]
Description=XDP Firewall DDoS Protection
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/xdp-firewall --config /etc/xdp-firewall.conf
ExecStop=/usr/local/sbin/xdp-firewall --unload
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now xdp-firewall
echo "✅ XDP-Firewall service enabled & started"

# ----------------------------------------------------------
# 6. IPSET + IPTABLES HARDENING
# ----------------------------------------------------------
ipset create blacklist hash:ip timeout 3600 2>/dev/null || true
iptables -I INPUT -m set --match-set blacklist src -j DROP 2>/dev/null || true

# SYN/UDP/HTTP rate-limit
iptables -A INPUT -p tcp --syn -m limit --limit 2/s --limit-burst 6 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP
iptables -A INPUT -p udp -m limit --limit 10/s -j ACCEPT
iptables -A INPUT -p udp -j DROP
for p in 80 443 8080; do
    iptables -A INPUT -p tcp --dport $p -m conntrack --ctstate NEW -m recent --set
    iptables -A INPUT -p tcp --dport $p -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 30 -j SET --add-set blacklist src
done
echo "✅ iptables/ipset rules applied"

# ----------------------------------------------------------
# 7. FAIL2BAN LAYER-7 FILTER
# ----------------------------------------------------------
cat > /etc/fail2ban/filter.d/ptero-ddos.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|OPTIONS).*HTTP.*" (403|404|429|400)
ignoreregex =
EOF
cat >> /etc/fail2ban/jail.local <<'EOF'
[ptero-ddos]
enabled  = true
port     = 80,443,8080
filter   = ptero-ddos
logpath  = /var/log/nginx/access.log
maxretry = 10
findtime = 60
bantime  = 3600
EOF
systemctl restart fail2ban
echo "✅ fail2ban L7 filter active"

# ----------------------------------------------------------
# 8. SAVE RULES (persistent)
# ----------------------------------------------------------
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
if command -v apt &>/dev/null; then
    $INSTALL iptables-persistent -y && iptables-save > /etc/iptables/rules.v4
fi
echo "✅ Rules saved & persistent"

# ----------------------------------------------------------
# 9. DONE
# ----------------------------------------------------------
echo "🎉 SUPER DDoS SHIELD installed & running!"
echo "   Backup iptables: $BACKUP_DIR"
echo "   Config         : $CONFIG"
echo "   Service status : systemctl status xdp-firewall"
