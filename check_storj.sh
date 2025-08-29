cat > ~/check_storj.sh <<'EOF'
#!/bin/bash
echo "=== CEK STORJ NODE ==="
docker ps --filter "name=storagenode"
docker inspect storagenode --format 'Status: {{.State.Status}}, StartedAt: {{.State.StartedAt}}' 2>/dev/null || true
echo "----- tail log -----"
docker logs --tail=20 storagenode 2>/dev/null || true
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):14002"
EOF
chmod +x ~/check_storj.sh
