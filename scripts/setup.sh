#!/bin/bash
# ================================================================
# setup.sh — Setup awal Docker Multi-Site Server
#
# Jalankan SEKALI saat pertama kali setup server baru.
# Kompatibel dengan Ubuntu 20.04, 22.04, 24.04
#
# Usage:
#   chmod +x scripts/setup.sh
#   ./scripts/setup.sh
# ================================================================

set -e

# ---- Warna untuk output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "================================================================"
echo "  🐳 Docker Server Kit — Setup"
echo "================================================================"
echo ""

# ---- Cek OS ----
if [ ! -f /etc/os-release ]; then
    log_error "OS tidak dikenali. Script ini hanya untuk Ubuntu."
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    log_error "Script ini hanya untuk Ubuntu. OS kamu: $ID"
fi

log_info "OS terdeteksi: Ubuntu $VERSION_ID"

# ---- Cek apakah sudah ada Docker ----
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    log_warn "Docker sudah terinstall (versi $DOCKER_VERSION). Skip instalasi."
else
    # ---- Install Docker ----
    echo ""
    log_info "Menginstall Docker..."

    sudo apt-get update -y -qq
    sudo apt-get install -y -qq \
        ca-certificates curl gnupg lsb-release apt-transport-https

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    log_success "Docker berhasil diinstall."
fi

# ---- Tambah user ke group docker ----
echo ""
if groups "$USER" | grep -q '\bdocker\b'; then
    log_warn "User '$USER' sudah ada di group docker. Skip."
else
    log_info "Menambahkan '$USER' ke group docker..."
    sudo usermod -aG docker "$USER"
    log_success "User '$USER' ditambahkan ke group docker."
    NEED_RELOGIN=true
fi

# ---- Buat Docker network global ----
echo ""
log_info "Memeriksa Docker network 'proxy-network'..."
if docker network ls | grep -q "proxy-network"; then
    log_warn "Network 'proxy-network' sudah ada. Skip."
else
    docker network create proxy-network
    log_success "Network 'proxy-network' berhasil dibuat."
fi

# ---- Setup direktori /srv ----
echo ""
log_info "Menyiapkan direktori /srv..."
sudo mkdir -p /srv/proxy/conf.d
sudo mkdir -p /srv/sites

# Salin file proxy ke /srv/proxy
sudo cp -r "$PROJECT_DIR/proxy/." /srv/proxy/

# Beri ownership ke current user
sudo chown -R "$USER:$USER" /srv/

log_success "Direktori /srv siap."

# ---- Salin scripts ke /srv ----
sudo cp "$SCRIPT_DIR/new-site.sh"    /srv/new-site.sh
sudo cp "$SCRIPT_DIR/remove-site.sh" /srv/remove-site.sh
sudo cp "$SCRIPT_DIR/list-sites.sh"  /srv/list-sites.sh
sudo chmod +x /srv/new-site.sh /srv/remove-site.sh /srv/list-sites.sh
sudo chown "$USER:$USER" /srv/new-site.sh /srv/remove-site.sh /srv/list-sites.sh

log_success "Scripts helper tersalin ke /srv/"

# ---- Verifikasi ----
echo ""
echo "================================================================"
echo -e "  ${GREEN}✅ Setup selesai!${NC}"
echo "================================================================"
echo ""

if [ "$NEED_RELOGIN" = true ]; then
    echo -e "  ${YELLOW}⚠️  PENTING: Logout dan login ulang agar permission Docker aktif:${NC}"
    echo ""
    echo "     exit"
    echo "     # Login lagi, lalu lanjutkan:"
    echo ""
fi

echo "  Langkah selanjutnya:"
echo ""
echo "  1. Jalankan Nginx proxy:"
echo "     cd /srv/proxy && docker compose up -d"
echo ""
echo "  2. Tambah website baru:"
echo "     /srv/new-site.sh nama-site domain.local 8000"
echo ""
echo "  3. Setup /etc/hosts di komputer kamu:"
echo "     $(hostname -I | awk '{print $1}')   domain.local"
echo ""
echo "  📖 Dokumentasi lengkap: docs/"
echo ""