#!/bin/bash
set -euo pipefail

### === EDIT 3 VARIABEL INI SEBELUM JALANKAN ===
WALLET="0x5534E4Dc87F591076843F2Cfbbfb842a91096ec6"     # <-- ganti dengan alamat MetaMask (0x...)
EMAIL="rizkiwahyuariyanto0030@gmail.com"      # <-- ganti dengan email aktif
STORAGE="900GB"                    # <-- ganti ukuran yang mau disediakan (contoh 800GB)
### ==========================================

echo "== START: Storj node installer (final) =="

# 1) update & basic installs
echo "[1/9] Update system & install packages..."
apt update -y
apt upgrade -y
apt install -y curl wget unzip docker.io ufw util-linux e2fsprogs

systemctl enable --now docker

# 2) detect HDD partition automatically (choose largest non-root disk/partition)
echo "[2/9] Detect HDD partition (auto)..."
# prefer usb partition; fallback to largest non-root partition
DEVICE=""
# try find usb-partitions
DEVICE_CAND=$(lsblk -dpno NAME,TRAN,TYPE | awk '$2=="usb" && $3=="part" {print $1; exit}')
if [ -z "$DEVICE_CAND" ]; then
  # fallback: largest partition that is not the root filesystem
  DEVICE_CAND=$(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="part"{print $1" "$2}' | sort -k2 -h | tail -n1 | awk '{print $1}')
fi
if [ -n "$DEVICE_CAND" ] && [ -b "$DEVICE_CAND" ]; then
  DEVICE="$DEVICE_CAND"
else
  echo "ERROR: Gagal deteksi partition HDD otomatis."
  echo "Silakan cek 'lsblk' lalu set DEVICE manual di script dan jalankan ulang."
  exit 1
fi
echo " -> akan digunakan device: $DEVICE"

# 3) check filesystem, do NOT auto-format (safer)
echo "[3/9] Periksa filesystem di $DEVICE..."
FSTYPE=$(blkid -s TYPE -o value "$DEVICE" 2>/dev/null || true)
if [ -z "$FSTYPE" ]; then
  echo "NOTICE: Tidak terdeteksi filesystem di $DEVICE."
  echo "Jika Anda ingin memformat ke ext4 (DATA AKAN HILANG), jalankan manual:"
  echo "  sudo mkfs.ext4 -F $DEVICE"
  echo "Setelah diformat, jalankan skrip lagi."
  exit 1
fi
echo " -> Filesystem terdeteksi: $FSTYPE"

# 4) mount ke /mnt/storj via UUID (agar persistent)
echo "[4/9] Mount HDD ke /mnt/storj dan set fstab..."
mkdir -p /mnt/storj
UUID=$(blkid -s UUID -o value "$DEVICE")
if ! grep -q "$UUID" /etc/fstab 2>/dev/null; then
  echo "UUID=$UUID /mnt/storj $FSTYPE defaults 0 2" >> /etc/fstab
fi
mount -a
sleep 1
if ! mountpoint -q /mnt/storj; then
  echo "ERROR: /mnt/storj gagal di-mount. Periksa /etc/fstab & device."
  exit 1
fi
echo " -> /mnt/storj ter-mount (df -h):"
df -h /mnt/storj || true

# 5) buat folder config + storage
echo "[5/9] Membuat folder config & storage di HDD..."
mkdir -p /mnt/storj/config /mnt/storj/storage
chown -R root:root /mnt/storj
chmod -R 750 /mnt/storj

# 6) setup firewall (ufw) dan buka port Storj
echo "[6/9] Setup firewall (ufw) dan buka port 28967, 14002..."
if ! command -v ufw >/dev/null 2>&1; then
  apt install -y ufw
fi
ufw allow OpenSSH
ufw allow 28967/tcp
ufw allow 28967/udp
ufw allow 14002/tcp
ufw --force enable
ufw status verbose

# 7) generate identity (download identity tool ARM64, buat identity)
echo "[7/9] Download identity tool & generate identity..."
IDENT_WORKDIR="/root/storj-identity"
mkdir -p "$IDENT_WORKDIR"
cd "$IDENT_WORKDIR"

IDENT_TARBALL_URL="https://github.com/storj/storj/releases/latest/download/identity_linux_arm64.tar.gz"
if ! wget -q -O identity.tar.gz "$IDENT_TARBALL_URL"; then
  echo "ERROR: gagal download identity tool dari $IDENT_TARBALL_URL"
  echo "Silakan download manual di laptop lalu scp ke $IDENT_WORKDIR"
  exit 1
fi
tar -xzf identity.tar.gz
# find 'identity' binary
IDENT_BIN=$(find . -maxdepth 2 -type f -name 'identity' -print -quit || true)
if [ -z "$IDENT_BIN" ]; then
  echo "ERROR: binary identity tidak ditemukan setelah ekstrak."
  ls -la
  exit 1
fi
chmod +x "$IDENT_BIN"
# create identity (this will create folder ./storagenode)
"$IDENT_BIN" create storagenode || true
# verify (may be non-critical)
"$IDENT_BIN" verify storagenode || echo "Info: verify returned non-zero (ok to continue without token)."

# move identity to storage location for container
DEST_ID="/root/.local/share/storj/identity/storagenode"
mkdir -p "$(dirname "$DEST_ID")"
rm -rf "$DEST_ID"
mv ./storagenode "$DEST_ID"
chmod -R 700 "$(dirname "$DEST_ID")"
echo " -> identity placed at $DEST_ID"

# 8) create starter script that waits mount and starts container
echo "[8/9] Membuat starter script & systemd service..."
cat > /usr/local/bin/storj-starter.sh <<'STORJSTART'
#!/bin/bash
set -e
# wait for mount
WAIT=0
MAX=60
while ! mountpoint -q /mnt/storj; do
  echo "Waiting for /mnt/storj..."
  sleep 2
  WAIT=$((WAIT+2))
  if [ $WAIT -ge $MAX ]; then
    echo "Error: /mnt/storj not mounted after $MAX seconds"
    exit 1
  fi
done
mkdir -p /mnt/storj/config /mnt/storj/storage
chmod 750 /mnt/storj/config /mnt/storj/storage

# start or create container
if docker ps -a --format '{{.Names}}' | grep -Eq '^storagenode$'; then
  echo "Starting existing storagenode container..."
  docker restart storagenode || docker start storagenode
else
  echo "Creating storagenode container..."
  docker run -d --restart unless-stopped --stop-timeout 300 \
    -p 28967:28967/tcp \
    -p 28967:28967/udp \
    -p 14002:14002 \
    -e WALLET="${WALLET}" \
    -e EMAIL="${EMAIL}" \
    -e ADDRESS="$(curl -s ifconfig.me 2>/dev/null || echo '0.0.0.0'):28967" \
    -e STORAGE="${STORAGE}" \
    --mount type=bind,source=/root/.local/share/storj/identity/storagenode,destination=/app/identity,readonly \
    --mount type=bind,source=/mnt/storj/config,destination=/app/config \
    --mount type=bind,source=/mnt/storj/storage,destination=/app/storage \
    --name storagenode storjlabs/storagenode:latest
fi
STORJSTART

chmod +x /usr/local/bin/storj-starter.sh

cat > /etc/systemd/system/storj-starter.service <<'STORJSERVICE'
[Unit]
Description=Storj starter (wait for mount then start container)
After=network.target docker.service local-fs.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/storj-starter.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
STORJSERVICE

systemctl daemon-reload
systemctl enable --now storj-starter.service

# 9) cron backup: restart if crash (extra safety)
echo "[9/9] Setup cron auto-restart cek (setiap 30 menit)..."
crontab -l > /tmp/mycron 2>/dev/null || true
if ! grep -q "docker restart storagenode" /tmp/mycron 2>/dev/null; then
  echo "*/30 * * * * docker restart storagenode >/dev/null 2>&1" >> /tmp/mycron
  crontab /tmp/mycron
fi
rm -f /tmp/mycron

echo ""
echo "=== FINISHED: Storj node installer ==="
echo "Periksa status: docker ps | grep storagenode"
echo "Lihat log: docker logs -f storagenode"
echo "Dashboard (LAN): http://$(hostname -I | awk '{print $1}'):14002"
echo ""
echo "NOTE: jika ingin mengakses dari internet, forward port 28967 TCP+UDP di router."
