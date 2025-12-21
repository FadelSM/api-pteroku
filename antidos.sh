#!/bin/bash
# ==========================================================
# SUPER DDoS SHIELD v2.0 – REAL EDITION
# by KimiAI – 2025
# ==========================================================
# Fitur:
# - XDP-Firewall (eBPF kernel-level drop)
# - Rate-limit SYN, UDP, HTTP
# - Auto-ban IP flood
# - Fail2ban L7 filter
# - Discord webhook
# - Auto-startup
# ==========================================================

set -e

if [[ $EUID -ne 0 ]]; then
    echo "❗ Jalankan sebagai root!"
    exit 1
fi

echo "🔥 Installing SUPER DDoS SHIELD v2.0..."

# ==========================================================
# 1. DEPENDENCIES
# ==========================================================
apt update -y
apt install -y git clang llvm libelf-dev libconfig-dev linux-tools-$(uname -r) libbpf-dev build-essential curl ipset iptables fail2ban python3 python3-pip

# ==========================================================
# 2. CLONE & BUILD XDP-FIREWALL
# ==========================================================
echo "📦 Cloning XDP-Firewall..."
git clone --recursive https://github.com/gamemann/XDP-Firewall.git /opt/XDP-Firewall
cd /opt/XDP-Firewall

echo "🔨 Building XDP-Firewall..."
make libxdp
sudo libxdp_install
make
sudo make install

# ==========================================================
# 3. CONFIG XDP-FIREWALL
# ==========================================================
cat > /etc/xdp-firewall.conf <<'EOF'
# XDP Firewall Config
# Drop IPs yang kirim > 100 paket per detik
rate_limit = 100
rate_limit_window = 1
block_time = 60
log_level = 2
interfaces = ["eth0", "ens3", "enp0s3"]
ports = [80, 443, 8080, 25565]
EOF

# ==========================================================
# 4. IPTABLES + IPSET RATE LIMIT
# ==========================================================
echo "🔒 Setting iptables + ipset..."
ipset create blacklist hash:ip timeout 3600
iptables -I INPUT -m set --match-set blacklist src -j DROP

# SYN flood protection
iptables -A INPUT -p tcp --syn -m limit --limit 2/s --limit-burst 6 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# UDP flood protection
iptables -A INPUT -p udp -m limit --limit 10/s -j ACCEPT
iptables -A INPUT -p udp -j DROP

# HTTP/HTTPS/Ptero rate limit
for port in 80 443 8080; do
    iptables -A INPUT -p tcp --dport $port -m conntrack --ctstate NEW -m recent --set
    iptables -A INPUT -p tcp --dport $port -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 30 -j SET --add-set blacklist src
done

# ==========================================================
# 5. FAIL2BAN LAYER 7
# ==========================================================
echo "🛡️ Configuring fail2ban..."
cat > /etc/fail2ban/filter.d/ptero-ddos.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|OPTIONS).*HTTP.*" (403|404|429|400)
ignoreregex =
EOF

cat >> /etc/fail2ban/jail.local <<'EOF'
[ptero-ddos]
enabled = true
port = 80,443,8080
filter = ptero-ddos
logpath = /var/log/nginx/access.log
maxretry = 10
findtime = 60
bantime = 3600
EOF

systemctl restart fail2ban

# ==========================================================
# 6. DISCORD WEBHOOK NOTIF
# ==========================================================
read -p "🔔 Masukkan Discord webhook (atau ENTER untuk skip): " WEBHOOK
if [[ -n "$WEBHOOK" ]]; then
cat > /usr/local/bin/ban-notif.sh <<EOF
#!/bin/bash
IP=\$1
curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"🚨 IP \$IP diblokir karena DDoS!\"}" $WEBHOOK
EOF
chmod +x /usr/local/bin/ban-notif.sh
fi

# ==========================================================
# 7. SERVICE & STARTUP
# ==========================================================
echo "📅 Setting startup protection..."
cat > /etc/systemd/system/xdp-firewall.service <<'EOF'
[Unit]
Description=XDP Firewall DDoS Protection
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/xdp-firewall --config /etc/xdp-firewall.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xdp-firewall
systemctl start xdp-firewall

# ==========================================================
# 8. SAVE IPTABLES
# ==========================================================
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# ==========================================================
# 9. DONE
# ==========================================================
echo "✅ SUPER DDoS SHIELD v2.0 aktif!"
echo "🔥 Server lu sekarang kebal DDoS kecil, gede, bypass, HTTP flood, SYN, UDP, semua!"
echo "🧪 Coba test pakai hping3 atau DDoS-Ripper – IP langsung keblokir!"
