#!/bin/bash
# ================================================================
# ssl-local.sh — Generate SSL sertifikat lokal dengan mkcert
#
# Untuk: Local development / VirtualBox / simulasi production
#        (TANPA domain asli, TANPA Let's Encrypt)
#
# Prasyarat:
#   - Nginx proxy sudah berjalan (docker compose up -d)
#   - Nginx config untuk domain sudah ada di /srv/proxy/conf.d/
#     (gunakan new-site.sh --ssl untuk generate config HTTPS)
#
# Usage:
#   ./ssl-local.sh <domain1> [domain2] [domain3] ...
#
# Contoh:
#   ./ssl-local.sh auth.192.168.56.101.nip.io
#   ./ssl-local.sh auth.192.168.56.101.nip.io docs.192.168.56.101.nip.io
#   ./ssl-local.sh 192.168.56.101
#
# Setelah selesai:
#   Import rootCA.pem ke Windows agar browser percaya sertifikat.
#   Instruksi lengkap: docs/ssl.md
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

CERTS_DIR="/srv/proxy/certs"

# ---- Validasi input ----
if [ $# -eq 0 ]; then
    echo ""
    echo "Usage: $0 <domain1> [domain2] [domain3] ..."
    echo ""
    echo "Contoh:"
    echo "  $0 auth.192.168.56.101.nip.io"
    echo "  $0 auth.192.168.56.101.nip.io docs.192.168.56.101.nip.io"
    echo "  $0 192.168.56.101"
    echo ""
    echo "📖 Panduan lengkap: docs/ssl.md"
    echo ""
    exit 1
fi

echo ""
echo "================================================================"
echo "  🔐 SSL Local Setup — mkcert"
echo "================================================================"
echo ""

# ================================================================
# STEP 1 — Install mkcert
# ================================================================
log_step "Step 1: Install mkcert"

if command -v mkcert &>/dev/null; then
    MKCERT_VER=$(mkcert --version 2>/dev/null || echo "unknown")
    log_warn "mkcert sudah terinstall ($MKCERT_VER). Skip install."
else
    log_info "Menginstall mkcert..."

    # Deteksi arsitektur CPU
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  MKCERT_ARCH="amd64" ;;
        aarch64) MKCERT_ARCH="arm64" ;;
        armv7l)  MKCERT_ARCH="arm" ;;
        *)       log_error "Arsitektur tidak didukung: $ARCH" ;;
    esac

    # Install dependensi libnss3-tools (untuk Firefox support)
    sudo apt-get install -y -qq libnss3-tools 2>/dev/null || true

    # Download binary dari GitHub releases
    MKCERT_VERSION="v1.4.4"
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${MKCERT_ARCH}"

    log_info "Download mkcert ${MKCERT_VERSION} (linux-${MKCERT_ARCH})..."
    sudo curl -fsSL -o /usr/local/bin/mkcert "$MKCERT_URL"
    sudo chmod +x /usr/local/bin/mkcert

    log_success "mkcert ${MKCERT_VERSION} berhasil diinstall."
fi

# ================================================================
# STEP 2 — Install Local CA ke system trust store
# ================================================================
log_step "Step 2: Install Local CA"

mkcert -install
CAROOT=$(mkcert -CAROOT)
log_success "Local CA tersimpan di: $CAROOT"

# ================================================================
# STEP 3 — Siapkan direktori sertifikat
# ================================================================
log_step "Step 3: Siapkan direktori sertifikat"

sudo mkdir -p "$CERTS_DIR"
sudo chown -R "$USER:$USER" "$CERTS_DIR"
log_success "Direktori $CERTS_DIR siap."

# ================================================================
# STEP 4 — Generate sertifikat per domain
# ================================================================
log_step "Step 4: Generate sertifikat"

TMPDIR_CERT=$(mktemp -d)
trap "rm -rf $TMPDIR_CERT" EXIT

for DOMAIN in "$@"; do
    log_info "Generate sertifikat untuk: ${CYAN}$DOMAIN${NC}"

    DOMAIN_CERT_DIR="$CERTS_DIR/$DOMAIN"
    mkdir -p "$DOMAIN_CERT_DIR"

    # Generate ke tmpdir (nama file output mkcert tidak predictable)
    cd "$TMPDIR_CERT"
    mkcert "$DOMAIN"

    # Cari file yang dihasilkan
    CERT_FILE=$(ls "$TMPDIR_CERT"/*.pem 2>/dev/null | grep -v "\-key" | head -1)
    KEY_FILE=$(ls "$TMPDIR_CERT"/*-key.pem 2>/dev/null | head -1)

    if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
        log_error "File sertifikat tidak ditemukan untuk $DOMAIN"
    fi

    # Salin ke direktori standar dengan nama yang konsisten
    cp "$CERT_FILE" "$DOMAIN_CERT_DIR/fullchain.pem"
    cp "$KEY_FILE"  "$DOMAIN_CERT_DIR/privkey.pem"

    # Bersihkan tmpdir untuk domain berikutnya
    rm -f "$TMPDIR_CERT"/*.pem

    log_success "Sertifikat siap: $DOMAIN_CERT_DIR/"
done

# ================================================================
# STEP 5 — Reload Nginx
# ================================================================
log_step "Step 5: Reload Nginx"

if docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    if docker exec nginx-proxy nginx -t 2>/dev/null; then
        docker exec nginx-proxy nginx -s reload
        log_success "Nginx berhasil di-reload."
    else
        log_warn "Nginx config test gagal. Cek konfigurasi site HTTPS kamu."
        log_warn "Jalankan manual: docker exec nginx-proxy nginx -t"
    fi
else
    log_warn "Container nginx-proxy tidak ditemukan."
    log_warn "Jalankan proxy dulu: cd /srv/proxy && docker compose up -d"
fi

# ================================================================
# SUMMARY & Instruksi Windows
# ================================================================
echo ""
echo "================================================================"
echo -e "  ${GREEN}✅ Sertifikat SSL lokal berhasil dibuat!${NC}"
echo "================================================================"
echo ""
echo "  Sertifikat tersimpan di:"
for DOMAIN in "$@"; do
    echo "    📄 $CERTS_DIR/$DOMAIN/"
done
echo ""
echo "================================================================"
echo -e "  ${YELLOW}⚠️  Import CA ke Windows agar browser percaya${NC}"
echo "================================================================"
echo ""
echo "  File CA ada di server:"
echo "    $CAROOT/rootCA.pem"
echo ""
echo "  1. Copy ke Windows:"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "     scp $USER@$SERVER_IP:$CAROOT/rootCA.pem %USERPROFILE%\\Downloads\\"
echo ""
echo "  2. Di Windows PowerShell (sebagai Administrator):"
echo "     certutil -addstore -f \"ROOT\" %USERPROFILE%\\Downloads\\rootCA.pem"
echo ""
echo "  3. Atau manual: double-click rootCA.pem"
echo "     → Install Certificate → Local Machine"
echo "     → Place in: Trusted Root Certification Authorities"
echo ""
echo "  4. Restart browser (tutup semua jendela, buka ulang)"
echo ""
echo "  📖 Panduan lengkap: docs/ssl.md"
echo ""
