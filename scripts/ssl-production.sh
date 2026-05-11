#!/bin/bash
# ================================================================
# ssl-production.sh — Issue sertifikat SSL dari Let's Encrypt
#
# Untuk: VPS production dengan domain asli yang sudah pointing
#        ke IP public server.
#
# Prasyarat:
#   - Domain A record sudah mengarah ke IP server
#   - Port 80 dan 443 terbuka di firewall (ufw allow 80 443)
#   - Nginx proxy sudah berjalan (docker compose up -d)
#   - Nginx config untuk domain sudah ada & listen port 80
#
# Usage:
#   ./ssl-production.sh <domain> <email> [--staging]
#
# Contoh:
#   ./ssl-production.sh example.com admin@example.com
#   ./ssl-production.sh auth.example.com admin@example.com
#   ./ssl-production.sh example.com admin@example.com --staging
#
# Flag --staging: Gunakan Let's Encrypt staging server untuk testing.
#   Sertifikat tidak valid di browser, tapi tidak kena rate limit.
#   Gunakan ini dulu sebelum issue sertifikat asli!
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step()    { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

DOMAIN="$1"
EMAIL="$2"
STAGING_FLAG="$3"

CERTS_DIR="/srv/proxy/certs"
CERTBOT_WWW="/srv/proxy/certbot-www"

# ---- Validasi input ----
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo ""
    echo "Usage: $0 <domain> <email> [--staging]"
    echo ""
    echo "Contoh:"
    echo "  $0 example.com admin@example.com"
    echo "  $0 auth.example.com admin@example.com"
    echo "  $0 example.com admin@example.com --staging   # testing dulu"
    echo ""
    echo "📖 Panduan lengkap: docs/ssl.md"
    echo ""
    exit 1
fi

echo ""
echo "================================================================"
echo "  🔐 SSL Production Setup — Let's Encrypt"
echo "================================================================"
echo "  Domain  : $DOMAIN"
echo "  Email   : $EMAIL"
if [ "$STAGING_FLAG" = "--staging" ]; then
    echo -e "  Mode    : ${YELLOW}STAGING (sertifikat tidak valid, untuk testing)${NC}"
else
    echo "  Mode    : PRODUCTION"
fi
echo ""

# ================================================================
# STEP 1 — Verifikasi Nginx berjalan
# ================================================================
log_step "Step 1: Verifikasi Nginx proxy"

if ! docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    log_error "nginx-proxy tidak berjalan.\nJalankan: cd /srv/proxy && docker compose up -d"
fi
log_success "nginx-proxy berjalan."

# ================================================================
# STEP 2 — Verifikasi domain dapat diakses
# ================================================================
log_step "Step 2: Verifikasi domain"

log_info "Mengecek apakah $DOMAIN dapat diakses via HTTP..."
HTTP_STATUS=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" "http://$DOMAIN/" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "000" ]; then
    log_warn "Domain $DOMAIN tidak dapat diakses (timeout/error)."
    log_warn ""
    log_warn "Pastikan:"
    log_warn "  1. A record domain sudah mengarah ke IP server ini"
    log_warn "  2. Port 80 terbuka: sudo ufw allow 80"
    log_warn "  3. Nginx config untuk $DOMAIN ada di /srv/proxy/conf.d/"
    echo ""
    read -p "Lanjutkan quand meme? (y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1
else
    log_success "Domain $DOMAIN dapat diakses (HTTP $HTTP_STATUS)."
fi

# ================================================================
# STEP 3 — Siapkan direktori
# ================================================================
log_step "Step 3: Siapkan direktori"

mkdir -p "$CERTBOT_WWW"
sudo mkdir -p "$CERTS_DIR"
sudo chown -R "$USER:$USER" "$CERTS_DIR"
log_success "Direktori siap."

# ================================================================
# STEP 4 — Issue sertifikat via Certbot
# ================================================================
log_step "Step 4: Request sertifikat dari Let's Encrypt"

CERTBOT_EXTRA=""
if [ "$STAGING_FLAG" = "--staging" ]; then
    CERTBOT_EXTRA="--staging"
fi

log_info "Menjalankan Certbot (webroot method)..."
log_info "Pastikan Nginx config kamu sudah punya block:"
log_info "  location /.well-known/acme-challenge/ { root /var/www/certbot; }"
echo ""

docker run --rm \
    -v "$CERTBOT_WWW:/var/www/certbot" \
    -v "$CERTS_DIR:/etc/letsencrypt" \
    certbot/certbot:latest certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    $CERTBOT_EXTRA \
    -d "$DOMAIN"

log_success "Sertifikat berhasil di-issue!"

# ================================================================
# STEP 5 — Salin sertifikat ke direktori standar
# ================================================================
log_step "Step 5: Sinkronisasi ke direktori standar"

LIVE_CERT="$CERTS_DIR/live/$DOMAIN"
TARGET_DIR="$CERTS_DIR/$DOMAIN"

if [ -f "$LIVE_CERT/fullchain.pem" ]; then
    mkdir -p "$TARGET_DIR"
    cp "$LIVE_CERT/fullchain.pem" "$TARGET_DIR/fullchain.pem"
    cp "$LIVE_CERT/privkey.pem"   "$TARGET_DIR/privkey.pem"
    log_success "Sertifikat disalin ke $TARGET_DIR/"
else
    log_error "Sertifikat tidak ditemukan di $LIVE_CERT. Certbot mungkin gagal."
fi

# ================================================================
# STEP 6 — Setup cron auto-renewal
# ================================================================
log_step "Step 6: Setup auto-renewal cron"

CRON_JOB="0 0,12 * * * /srv/ssl-renew.sh >> /var/log/certbot-renew.log 2>&1"

if crontab -l 2>/dev/null | grep -q "ssl-renew.sh"; then
    log_warn "Cron renewal sudah ada. Skip."
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log_success "Cron renewal ditambahkan (cek setiap 12 jam)."
fi

# ================================================================
# STEP 7 — Reload Nginx
# ================================================================
log_step "Step 7: Aktifkan HTTPS — Reload Nginx"

if docker exec nginx-proxy nginx -t 2>/dev/null; then
    docker exec nginx-proxy nginx -s reload
    log_success "Nginx berhasil di-reload."
else
    log_warn "Nginx config test gagal!"
    log_warn "Cek apakah Nginx config untuk $DOMAIN sudah pakai format HTTPS."
    log_warn "  → Lihat contoh di: /srv/proxy/example.conf.template"
    log_warn "  → Panduan: docs/ssl.md"
fi

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo "================================================================"
if [ "$STAGING_FLAG" = "--staging" ]; then
    echo -e "  ${YELLOW}✅ STAGING selesai — Sertifikat belum valid di browser${NC}"
    echo "================================================================"
    echo ""
    echo "  Jika staging berhasil, jalankan ulang TANPA --staging:"
    echo "    $0 $DOMAIN $EMAIL"
else
    echo -e "  ${GREEN}✅ SSL Production untuk $DOMAIN berhasil!${NC}"
    echo "================================================================"
    echo ""
    echo "  Sertifikat : $TARGET_DIR/"
    echo "  Auto-renew : cron setiap 12 jam ✓"
    echo "  Log renew  : /var/log/certbot-renew.log"
    echo ""
    echo "  Verifikasi:"
    echo "    curl -I https://$DOMAIN"
    echo "    https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
fi
echo ""
