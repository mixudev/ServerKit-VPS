#!/bin/bash
# ================================================================
# ssl-renew.sh — Auto-renewal sertifikat Let's Encrypt
#
# Dipanggil otomatis oleh cron job setiap 12 jam.
# Certbot hanya memperbarui sertifikat yang expire < 30 hari.
# Tidak ada efek jika sertifikat masih valid.
#
# Setup cron (otomatis dilakukan oleh ssl-production.sh):
#   0 0,12 * * * /srv/ssl-renew.sh >> /var/log/certbot-renew.log 2>&1
#
# Jalankan manual:
#   /srv/ssl-renew.sh
# ================================================================

set -e

CERTS_DIR="/srv/proxy/certs"
CERTBOT_WWW="/srv/proxy/certbot-www"
TIMESTAMP="[$(date '+%Y-%m-%d %H:%M:%S')]"

echo ""
echo "$TIMESTAMP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$TIMESTAMP  Certbot Auto-Renewal Check"
echo "$TIMESTAMP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---- Pastikan certbot-www ada ----
mkdir -p "$CERTBOT_WWW"

# ---- Jalankan certbot renew ----
echo "$TIMESTAMP Menjalankan certbot renew..."

docker run --rm \
    -v "$CERTBOT_WWW:/var/www/certbot" \
    -v "$CERTS_DIR:/etc/letsencrypt" \
    certbot/certbot:latest renew \
    --quiet \
    --webroot \
    --webroot-path /var/www/certbot

echo "$TIMESTAMP Certbot renew selesai."

# ---- Sync sertifikat yang diperbarui ke direktori standar ----
echo "$TIMESTAMP Menyinkronkan sertifikat..."

LIVE_DIR="$CERTS_DIR/live"
if [ -d "$LIVE_DIR" ]; then
    for DOMAIN_DIR in "$LIVE_DIR"/*/; do
        DOMAIN=$(basename "$DOMAIN_DIR")
        TARGET="$CERTS_DIR/$DOMAIN"

        if [ -f "$DOMAIN_DIR/fullchain.pem" ]; then
            mkdir -p "$TARGET"
            cp -f "$DOMAIN_DIR/fullchain.pem" "$TARGET/fullchain.pem"
            cp -f "$DOMAIN_DIR/privkey.pem"   "$TARGET/privkey.pem"
            echo "$TIMESTAMP Sertifikat $DOMAIN disinkronkan."
        fi
    done
else
    echo "$TIMESTAMP Tidak ada sertifikat Let's Encrypt ditemukan. Skip sync."
fi

# ---- Reload Nginx ----
if docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    docker exec nginx-proxy nginx -s reload
    echo "$TIMESTAMP Nginx di-reload."
else
    echo "$TIMESTAMP WARN: nginx-proxy tidak berjalan. Reload manual diperlukan."
fi

echo "$TIMESTAMP ✅ Selesai."
echo ""
