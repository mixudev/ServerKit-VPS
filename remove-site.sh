#!/bin/bash
# ================================================================
# remove-site.sh — Hapus website dari server
#
# Usage:
#   ./remove-site.sh <nama-site> [--delete-data]
#
# Flags:
#   --delete-data   Hapus juga Docker volumes (data DB, dll.)
#                   PERINGATAN: tidak bisa di-undo!
#
# Contoh:
#   ./remove-site.sh toko-online              # hapus site, data aman
#   ./remove-site.sh toko-online --delete-data # hapus site + data
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
DELETE_DATA=false

if [ "$2" = "--delete-data" ]; then
    DELETE_DATA=true
fi

if [ -z "$SITE_NAME" ]; then
    echo ""
    echo "Usage: $0 <nama-site> [--delete-data]"
    echo ""
    echo "Contoh:"
    echo "  $0 toko-online              # hapus site, data volume tetap"
    echo "  $0 toko-online --delete-data # hapus site + hapus data volume"
    echo ""
    exit 1
fi

SITE_DIR="/srv/sites/$SITE_NAME"
PROXY_CONF="/srv/proxy/conf.d/${SITE_NAME}.conf"

if [ ! -d "$SITE_DIR" ]; then
    log_error "Site '$SITE_NAME' tidak ditemukan di $SITE_DIR"
fi

echo ""
echo "================================================================"
if [ "$DELETE_DATA" = true ]; then
    echo -e "  ${RED}⚠️  HAPUS SITE + DATA: $SITE_NAME${NC}"
else
    echo "  🗑️  Menghapus site: $SITE_NAME"
fi
echo "================================================================"
echo ""

# ---- Konfirmasi ----
if [ "$DELETE_DATA" = true ]; then
    echo -e "${RED}PERINGATAN: Semua data database dan volume akan dihapus permanen!${NC}"
fi
echo -n "Ketik nama site untuk konfirmasi: "
read CONFIRM

if [ "$CONFIRM" != "$SITE_NAME" ]; then
    log_warn "Konfirmasi tidak cocok. Dibatalkan."
    exit 0
fi

# ---- Stop dan hapus containers ----
if [ -f "$SITE_DIR/docker-compose.yml" ]; then
    log_info "Menghentikan containers..."
    cd "$SITE_DIR"
    if [ "$DELETE_DATA" = true ]; then
        docker compose down -v 2>/dev/null || true
    else
        docker compose down 2>/dev/null || true
    fi
    log_success "Containers dihentikan."
fi

# ---- Hapus Nginx config ----
if [ -f "$PROXY_CONF" ]; then
    rm -f "$PROXY_CONF"
    log_success "Nginx config dihapus: $PROXY_CONF"
fi

# ---- Reload Nginx ----
if docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    docker exec nginx-proxy nginx -s reload
    log_success "Nginx di-reload."
fi

# ---- Hapus folder site ----
rm -rf "$SITE_DIR"
log_success "Folder site dihapus: $SITE_DIR"

echo ""
echo "================================================================"
echo -e "  ${GREEN}✅ Site '$SITE_NAME' berhasil dihapus.${NC}"
echo "================================================================"
echo ""