#!/bin/bash
# ====== STORJ NODE FINAL FIXED AUTO START (Armbian) ======
# EDIT: ganti WALLET & EMAIL sebelum jalankan

WALLET="ALAMAT_WALLET_BINANCE_STORJ"  # <-- ganti
EMAIL="email@domain.com"              # <-- ganti
STORAGE="900GB"
IDENTITY="/root/.local/share/storj/identity/storagenode"
STORAGE_DIR="/media/hdd/storj"
DEVICE="/dev/sda1"                     # ganti sesuai HDD (cek lsblk)

echo "🚀 Mulai setup Storj node..."

# 1) Update sistem
apt update && apt upgrade -y

# 2) Install Docker jika belum ada
if ! command -v docker >/dev/null 2>&1; then
    echo "📦 Docker belum terinstall, memasang Docker..."
    apt install -y docker.io curl jq
    systemctl enable docker
    systemctl start docker
fi

# 3) Mount HDD & buat folder storage
mkdir -p /media/hdd
UUID=$(blkid -s UUID -o value $DEVICE 2>/dev/null || echo "")
if [ -z "$UUID" ]; then
    echo "❌ ERROR: HDD $DEVICE tidak ditemukan. Pastikan terhubung dan lsblk dicek."
    exit 1
fi
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID /media/hdd ext4 defaults 0 2" >> /etc/fstab
fi
mount -a

# Buat folder storj di HDD
mkdir -p $STORAGE_DIR
chmod 755 $STORAGE_DIR

# Buat folder identity
mkdir -p $IDENTITY
chmod 755 $IDENTITY

# 4) Jalankan/Restart node Docker
if docker ps -a --format '{{.Names}}' | grep -Eq "^storagenode\$"; then
    echo "Container storagenode sudah ada, restart container..."
    docker restart storagenode
else
    echo "Membuat container storagenode baru..."
    docker run -d --restart unless-stopped --stop-timeout 300 \
        -p 28967:28967 \
        -p 14002:14002 \
        -e WALLET="$WALLET" \
        -e EMAIL="$EMAIL" \
        -e ADDRESS="0.0.0.0:28967" \
        -e STORAGE="$STORAGE" \
        --mount type=bind,source=$IDENTITY,destination=/app/identity \
        --mount type=bind,source=$STORAGE_DIR,destination=/app/config \
        --name storagenode storjlabs/storagenode:latest
fi

# 5) Setup cron auto-restart tiap 30 menit (backup)
crontab -l > /tmp/mycron 2>/dev/null || true
grep -q "docker restart storagenode" /tmp/mycron || echo "*/30 * * * * docker restart storagenode >/dev/null 2>&1" >> /tmp/mycron
crontab /tmp/mycron
rm -f /tmp/mycron

# 6) Setup systemd service untuk auto start saat reboot/listrik padam
SERVICE_FILE="/etc/systemd/system/storagenode.service"
if [ ! -f "$SERVICE_FILE" ]; then
    cat <<EOL > $SERVICE_FILE
[Unit]
Description=Storj Node
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a storagenode
ExecStop=/usr/bin/docker stop -t 300 storagenode

[Install]
WantedBy=multi-user.target
EOL
    systemctl daemon-reload
    systemctl enable storagenode.service
    systemctl start storagenode.service
fi

echo "✅ Instalasi selesai!"
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):14002"
echo "Cek container: docker ps | grep storagenode"

