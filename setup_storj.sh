#!/bin/bash
# ============================
# Storj Node Setup - Armbian
# Versi Fix (Auto Detect HDD)
# ============================

set -e

echo "=== Storj Node Setup Started ==="

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install dependencies
sudo apt install -y curl wget unzip util-linux e2fsprogs docker.io

# 3. Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# 4. Detect HDD
echo "=== Detecting HDD ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
DEVICE=$(lsblk -dn -o NAME,TYPE | grep "disk" | awk '{print $1}' | head -n 1)

if [ -z "$DEVICE" ]; then
    echo "❌ ERROR: Tidak ada HDD terdeteksi!"
    exit 1
fi

echo ">>> HDD ditemukan: /dev/$DEVICE"
read -p "Apakah benar ini HDD yang ingin dipakai? (/dev/$DEVICE) [y/n]: " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
    echo "Silakan cek dengan 'lsblk' lalu masukkan manual."
    read -p "Masukkan nama device HDD (contoh: sda1): " DEVICE
fi

# 5. Format jika perlu (opsional)
read -p "Apakah ingin format HDD /dev/$DEVICE ke ext4? (hapus semua data) [y/n]: " FORMAT
if [[ "$FORMAT" == "y" ]]; then
    sudo mkfs.ext4 /dev/$DEVICE
fi

# 6. Mount HDD
sudo mkdir -p /mnt/storj
sudo mount /dev/$DEVICE /mnt/storj

# 7. Tambahkan ke fstab agar auto-mount saat reboot
echo "/dev/$DEVICE /mnt/storj ext4 defaults 0 0" | sudo tee -a /etc/fstab

echo "=== HDD berhasil di-mount ke /mnt/storj ==="
df -h | grep /mnt/storj

# 8. Jalankan Storj Docker Node (edit email & wallet sesuai kebutuhan)
read -p "Masukkan email untuk Storj Node: " rizkiwahyuariyanto0030@gmail.com
read -p "Masukkan alamat wallet ERC20 (Metamask/TrustWallet): " 0x5534E4Dc87F591076843F2Cfbbfb842a91096ec6

docker run -d --restart unless-stopped --stop-timeout 300 \
    -p 28967:28967/tcp \
    -p 28967:28967/udp \
    -p 14002:14002 \
    -e WALLET="$WALLET" \
    -e EMAIL="$EMAIL" \
    -e ADDRESS="your_public_ip:28967" \
    -e STORAGE="800GB" \
    --mount type=bind,source=/mnt/storj,destination=/app/config \
    --mount type=bind,source=/mnt/storj,destination=/app/storage \
    --name storagenode storjlabs/storagenode:latest

echo "=== Storj Node Setup Selesai! ==="
echo "Cek dashboard di browser: http://IP_STB:14002"
