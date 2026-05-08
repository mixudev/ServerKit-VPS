#!/bin/bash
# ================================================================
# list-sites.sh — Tampilkan semua site dan status container
#
# Usage:
#   ./list-sites.sh
# ================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "================================================================"
echo -e "  ${BOLD}🐳 Docker Server Kit — Status Sites${NC}"
echo "================================================================"
echo ""

# ---- Cek proxy ----
echo -e "  ${BOLD}📡 Nginx Proxy${NC}"
if docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    echo -e "     Status : ${GREEN}● Running${NC}"
    PROXY_IP=$(docker inspect nginx-proxy --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' 2>/dev/null | tr ' ' '\n' | head -1)
    echo -e "     Network: proxy-network"
else
    echo -e "     Status : ${RED}● Stopped${NC}"
    echo -e "     Jalankan: cd /srv/proxy && docker compose up -d"
fi

echo ""

# ---- Cek sites ----
echo -e "  ${BOLD}🌐 Sites di /srv/sites/${NC}"
echo ""

SITES_DIR="/srv/sites"
if [ ! -d "$SITES_DIR" ] || [ -z "$(ls -A $SITES_DIR 2>/dev/null)" ]; then
    echo "     Belum ada site. Buat dengan: /srv/new-site.sh nama-site domain.local 8000"
else
    for site_dir in "$SITES_DIR"/*/; do
        site_name=$(basename "$site_dir")
        compose_file="$site_dir/docker-compose.yml"
        proxy_conf="/srv/proxy/conf.d/${site_name}.conf"

        echo -e "  ${BOLD}▸ $site_name${NC}"

        # Cek domain dari nginx config
        if [ -f "$proxy_conf" ]; then
            domain=$(grep "server_name" "$proxy_conf" | awk '{print $2}' | tr -d ';' | head -1)
            echo -e "    Domain : $domain"
        else
            echo -e "    Domain : ${YELLOW}(tidak ada nginx config)${NC}"
        fi

        # Cek status containers
        if [ -f "$compose_file" ]; then
            running=$(docker compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null | wc -l)
            total=$(docker compose -f "$compose_file" ps --services 2>/dev/null | wc -l)

            if [ "$running" -gt 0 ] && [ "$running" = "$total" ]; then
                echo -e "    Status : ${GREEN}● Running${NC} ($running/$total containers)"
            elif [ "$running" -gt 0 ]; then
                echo -e "    Status : ${YELLOW}● Partial${NC} ($running/$total containers running)"
            else
                echo -e "    Status : ${RED}● Stopped${NC}"
            fi
        else
            echo -e "    Status : ${YELLOW}(tidak ada docker-compose.yml)${NC}"
        fi

        echo ""
    done
fi

# ---- Ringkasan resource ----
echo "----------------------------------------------------------------"
echo -e "  ${BOLD}📊 Resource Usage${NC}"
echo ""
docker stats --no-stream --format "  {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | \
    grep -v "CONTAINER" | \
    awk 'BEGIN{printf "  %-30s %-10s %s\n", "CONTAINER", "CPU", "MEMORY"} {printf "  %-30s %-10s %s\n", $1, $2, $3}' \
    || echo "  Tidak ada container yang berjalan."

echo ""
echo "================================================================"
echo ""