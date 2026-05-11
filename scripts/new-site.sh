#!/bin/bash
# ================================================================
# new-site.sh — Scaffold website baru
#
# Usage:
#   ./new-site.sh <nama-site> <domain> <port-app>
#
# Contoh:
#   ./new-site.sh toko-online  toko.local    8000
#   ./new-site.sh blog-saya    blog.local    3000
#   ./new-site.sh api-service  api.local     8080
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SITE_NAME="$1"
DOMAIN="$2"
PORT="${3:-8000}"
SSL_MODE="${4:-}"
SITE_DIR="/srv/sites/$SITE_NAME"
PROXY_CONF="/srv/proxy/conf.d/${SITE_NAME}.conf"

# ---- Validasi input ----
if [ -z "$SITE_NAME" ] || [ -z "$DOMAIN" ]; then
    echo ""
    echo "Usage: $0 <nama-site> <domain> [port] [--ssl]"
    echo ""
    echo "Contoh:"
    echo "  $0 toko-online  toko.local        8000         # HTTP only"
    echo "  $0 toko-online  toko.example.com  8000  --ssl  # HTTPS"
    echo ""
    echo "Flag --ssl: Generate Nginx config dengan HTTPS + redirect."
    echo "  Jalankan ssl-local.sh atau ssl-production.sh untuk generate sertifikat."
    echo ""
    exit 1
fi

# Validasi nama site (hanya huruf, angka, dan tanda hubung)
if [[ ! "$SITE_NAME" =~ ^[a-z0-9-]+$ ]]; then
    log_error "Nama site hanya boleh mengandung huruf kecil, angka, dan tanda hubung."
fi

# Cek apakah site sudah ada
if [ -d "$SITE_DIR" ]; then
    log_error "Site '$SITE_NAME' sudah ada di $SITE_DIR"
fi

echo ""
echo "================================================================"
echo "  🌐 Membuat site baru: $SITE_NAME"
echo "================================================================"
echo "  Domain  : $DOMAIN"
echo "  Port    : $PORT"
if [ "$SSL_MODE" = "--ssl" ]; then
    echo "  Mode    : HTTPS (dengan redirect HTTP→HTTPS)"
else
    echo "  Mode    : HTTP only"
fi
echo "  Folder  : $SITE_DIR"
echo ""

# ---- Buat direktori ----
mkdir -p "$SITE_DIR/src"
log_success "Direktori $SITE_DIR dibuat."

# ---- Buat docker-compose.yml ----
cat > "$SITE_DIR/docker-compose.yml" << COMPOSE
# ============================================================
# Docker Compose — ${SITE_NAME}
# Domain: ${DOMAIN}
# ============================================================
# Edit file ini sesuai kebutuhan stack teknologi kamu.
# Lihat docs/adding-sites.md untuk template Laravel, FastAPI, dll.
# ============================================================

name: ${SITE_NAME}

services:
  app:
    build: .
    container_name: ${SITE_NAME}-app
    restart: unless-stopped
    volumes:
      - ./src:/app
    env_file: .env
    networks:
      - proxy-network   # terhubung ke proxy global
      - internal        # komunikasi internal antar service

  # Tambahkan service lain di sini (db, redis, worker, dll.)

volumes:
  # Definisikan volume untuk data persisten di sini
  # Contoh:
  # db_data:

networks:
  proxy-network:
    external: true      # network global, jangan dihapus
  internal:
    driver: bridge      # network privat khusus site ini
COMPOSE

log_success "docker-compose.yml dibuat."

# ---- Buat .env.example ----
cat > "$SITE_DIR/.env.example" << ENV
# ============================================================
# Environment Variables — ${SITE_NAME}
# Salin file ini: cp .env.example .env
# Lalu isi nilai yang sesuai.
# JANGAN commit file .env ke Git!
# ============================================================

APP_ENV=production
APP_PORT=${PORT}

# Database (sesuaikan jika pakai DB)
# DB_DATABASE=${SITE_NAME//-/_}_db
# DB_USERNAME=${SITE_NAME//-/_}_user
# DB_PASSWORD=ganti_dengan_password_kuat
# DB_ROOT_PASSWORD=ganti_dengan_root_password_kuat

# Redis (sesuaikan jika pakai Redis)
# REDIS_PASSWORD=ganti_dengan_redis_password
ENV

# Buat .env dari .env.example
cp "$SITE_DIR/.env.example" "$SITE_DIR/.env"
log_success ".env dan .env.example dibuat."

# ---- Buat Dockerfile placeholder ----
cat > "$SITE_DIR/Dockerfile" << DOCKERFILE
# ============================================================
# Dockerfile — ${SITE_NAME}
# Ganti isi file ini sesuai stack teknologi kamu.
# Lihat docs/adding-sites.md untuk contoh Dockerfile
# Laravel, FastAPI, Node.js, dll.
# ============================================================

# Contoh untuk Node.js:
# FROM node:20-alpine
# WORKDIR /app
# COPY src/package*.json ./
# RUN npm install
# COPY src/ .
# EXPOSE ${PORT}
# CMD ["node", "index.js"]

# Contoh untuk Python/FastAPI:
# FROM python:3.12-slim
# WORKDIR /app
# COPY src/requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
# COPY src/ .
# EXPOSE ${PORT}
# CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "${PORT}"]
DOCKERFILE

log_success "Dockerfile placeholder dibuat."

# ---- Buat Nginx config di proxy ----
if [ "$SSL_MODE" = "--ssl" ]; then
    # ---- Config HTTPS (dual block: redirect + SSL) ----
    cat > "$PROXY_CONF" << NGINX
# ============================================================
# Nginx Proxy Config — ${SITE_NAME}
# Domain: ${DOMAIN}
# Mode  : HTTPS
# ============================================================
# Setelah mengubah file ini, reload nginx:
#   docker exec nginx-proxy nginx -s reload
#
# Pastikan sertifikat sudah ada sebelum reload:
#   /srv/ssl-local.sh ${DOMAIN}       # untuk local
#   /srv/ssl-production.sh ${DOMAIN} email@example.com  # untuk production
# ============================================================

# Block 1: HTTP → redirect ke HTTPS
server {
    listen 80;
    server_name ${DOMAIN};

    # ACME challenge untuk Let's Encrypt renewal
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }

    access_log /var/log/nginx/${SITE_NAME}.access.log;
    error_log  /var/log/nginx/${SITE_NAME}.error.log;
}

# Block 2: HTTPS
server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate     /etc/nginx/certs/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${DOMAIN}/privkey.pem;
    include             /etc/nginx/conf.d/ssl-params.conf;

    location / {
        proxy_pass         http://${SITE_NAME}-app:${PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }

    access_log /var/log/nginx/${SITE_NAME}.access.log;
    error_log  /var/log/nginx/${SITE_NAME}.error.log;
}
NGINX
else
    # ---- Config HTTP only ----
    cat > "$PROXY_CONF" << NGINX
# ============================================================
# Nginx Proxy Config — ${SITE_NAME}
# Domain: ${DOMAIN}
# Mode  : HTTP only
# ============================================================
# Untuk aktifkan HTTPS, gunakan:
#   /srv/new-site.sh ${SITE_NAME} ${DOMAIN} ${PORT} --ssl
# ============================================================

server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass         http://${SITE_NAME}-app:${PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }

    access_log /var/log/nginx/${SITE_NAME}.access.log;
    error_log  /var/log/nginx/${SITE_NAME}.error.log;
}
NGINX
fi

log_success "Nginx config dibuat di $PROXY_CONF"

# ---- Buat .gitignore untuk site ini ----
cat > "$SITE_DIR/.gitignore" << GITIGNORE
.env
*.log
vendor/
node_modules/
__pycache__/
*.pyc
.DS_Store
storage/
GITIGNORE

log_success ".gitignore dibuat."

# ---- Summary ----
echo ""
echo "================================================================"
echo -e "  ${GREEN}✅ Site '$SITE_NAME' berhasil dibuat!${NC}"
echo "================================================================"
echo ""
echo "  Langkah selanjutnya:"
echo ""
echo "  1. Edit docker-compose.yml sesuai stack kamu:"
echo "     nano $SITE_DIR/docker-compose.yml"
echo ""
echo "  2. Isi file .env:"
echo "     nano $SITE_DIR/.env"
echo ""
echo "  3. Jalankan site:"
echo "     cd $SITE_DIR && docker compose up -d --build"
echo ""
echo "  4. Reload Nginx proxy (zero-downtime):"
echo "     docker exec nginx-proxy nginx -s reload"
echo ""
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ "$SSL_MODE" = "--ssl" ]; then
    echo "  5. Generate sertifikat SSL:"
    echo "     Local (mkcert) : /srv/ssl-local.sh $DOMAIN"
    echo "     Production     : /srv/ssl-production.sh $DOMAIN admin@email.com"
    echo ""
    echo "  6. Akses site:"
    echo "     https://$DOMAIN"
else
    echo "  5. Tambahkan ke /etc/hosts (jika domain lokal):"
    echo "     $SERVER_IP   $DOMAIN"
    echo ""
    echo "  6. Akses site:"
    echo "     http://$DOMAIN"
fi
echo ""
echo "  📖 Lihat docs/ssl.md untuk panduan SSL lengkap."
echo ""