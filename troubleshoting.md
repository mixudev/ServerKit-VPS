# Troubleshooting

Solusi untuk masalah-masalah umum yang sering terjadi.

---

## Container Tidak Mau Start

### Gejala
```
Error response from daemon: ...
```

### Diagnosis
```bash
# Lihat error detail
docker compose logs

# Atau container spesifik
docker logs nama-container

# Lihat status
docker compose ps
```

### Solusi Umum
```bash
# Rebuild image dari awal
docker compose down
docker compose build --no-cache
docker compose up -d

# Cek apakah port sudah dipakai proses lain
sudo ss -tlnp | grep :8000
sudo kill -9 PID_YANG_PAKAI_PORT
```

---

## Website Tidak Bisa Diakses di Browser

### Checklist

**1. Pastikan proxy running:**
```bash
docker ps | grep nginx-proxy
# Jika tidak ada:
cd /srv/proxy && docker compose up -d
```

**2. Pastikan container site running:**
```bash
docker ps | grep nama-site
# Jika tidak ada:
cd /srv/sites/nama-site && docker compose up -d
```

**3. Test nginx config:**
```bash
docker exec nginx-proxy nginx -t
# Harus output: "configuration file ... syntax is ok"
```

**4. Cek container terhubung ke proxy-network:**
```bash
docker network inspect proxy-network
# Lihat bagian "Containers", pastikan nama-site-nginx ada
```

**5. Cek /etc/hosts di komputer kamu:**
```
192.168.1.100   nama-site.local
```
Pastikan IP-nya benar (IP server, bukan IP lain).

**6. Test koneksi langsung:**
```bash
# Di komputer kamu
curl -v http://192.168.1.100 -H "Host: nama-site.local"
```

---

## Nginx Error Setelah Edit Config

### Gejala
Setelah reload, nginx tidak mau start atau website error.

### Diagnosis & Solusi
```bash
# Test config dulu SEBELUM reload
docker exec nginx-proxy nginx -t

# Jika ada error, akan ditunjukkan baris dan file yang bermasalah
# Perbaiki file tersebut:
nano /srv/proxy/conf.d/nama-site.conf

# Setelah diperbaiki, reload lagi
docker exec nginx-proxy nginx -s reload
```

### Error Umum Nginx
```
# "could not be resolved" — nama container tidak ditemukan
proxy_pass http://nama-container:80;
# → Pastikan nama container benar (cek: docker ps --format '{{.Names}}')
# → Pastikan container terhubung ke proxy-network

# "Connection refused" — port salah atau app belum ready
# → Cek port yang digunakan app: docker compose logs app
```

---

## Container Langsung Mati (Exit)

### Diagnosis
```bash
# Lihat exit code dan alasan
docker ps -a | grep nama-container
docker logs nama-container

# Lihat exit code
docker inspect nama-container --format '{{.State.ExitCode}}'
```

### Exit Code Umum
| Code | Artinya |
|------|---------|
| 0 | Selesai normal (bukan crash) |
| 1 | Error umum (cek logs) |
| 137 | Killed (OOM / kehabisan memory) |
| 139 | Segmentation fault |

### Jika OOM (Exit 137)
```bash
# Cek memory
free -h

# Lihat container mana yang pakai banyak memory
docker stats --no-stream

# Tambah swap jika RAM kurang (Ubuntu)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Database Tidak Bisa Dikoneksi

### Gejala
App error "Connection refused" atau "Access denied".

### Diagnosis
```bash
# Cek apakah DB container running
docker ps | grep nama-site-db

# Cek healthcheck
docker inspect nama-site-db | grep -A 5 Health

# Lihat log DB
docker logs nama-site-db
```

### Solusi
```bash
# Tunggu DB ready (terutama MySQL butuh waktu ~30 detik saat pertama kali)
docker compose logs -f db

# Cek environment variable
docker exec nama-site-db env | grep MYSQL

# Reset DB (HAPUS SEMUA DATA!)
docker compose down -v
docker compose up -d

# Test koneksi manual
docker exec -it nama-site-db mysql -u root -p
```

### Pastikan di docker-compose
```yaml
app:
  depends_on:
    db:
      condition: service_healthy   # ← tunggu sampai DB benar-benar ready
```

---

## Permission Error (Laravel Storage, dll.)

### Gejala
```
file_put_contents(...): Failed to open stream: Permission denied
```

### Solusi
```bash
# Fix permission di dalam container
docker exec nama-site-app chown -R www-data:www-data /var/www/html/storage
docker exec nama-site-app chmod -R 755 /var/www/html/storage
docker exec nama-site-app chmod -R 755 /var/www/html/bootstrap/cache
```

---

## Volume/Data Hilang Setelah `docker compose down`

### Penyebab
`docker compose down` tanpa flag `-v` seharusnya **tidak** menghapus named volumes. Tapi jika pakai anonymous volume (tanpa nama), data bisa hilang.

### Pastikan Volume Bernama
```yaml
# BENAR — named volume, data aman setelah down
volumes:
  - db_data:/var/lib/mysql

volumes:
  db_data:

# SALAH — anonymous volume, data hilang setelah down
volumes:
  - /var/lib/mysql
```

---

## Error: "network proxy-network not found"

### Penyebab
Network global belum dibuat, atau terhapus.

### Solusi
```bash
docker network create proxy-network
# Lalu restart site:
docker compose down && docker compose up -d
```

---

## Port Sudah Digunakan

### Gejala
```
Error: bind: address already in use
```

### Diagnosis
```bash
# Cek siapa yang pakai port 80
sudo ss -tlnp | grep :80

# Cek apakah ada container lain yang pakai port yang sama
docker ps | grep "0.0.0.0:80"
```

### Solusi
```bash
# Stop service yang pakai port tersebut
sudo systemctl stop nginx      # jika nginx terinstall langsung di Ubuntu
sudo systemctl stop apache2    # jika ada Apache

# Atau ganti port di docker-compose
ports:
  - "8080:80"                  # gunakan port lain
```

---

## Docker Compose Command Not Found

### Gejala
```
docker-compose: command not found
```

### Penyebab
Docker Compose v1 (`docker-compose`) sudah deprecated. Pakai v2 (`docker compose`).

### Solusi
```bash
# Pakai ini (tanpa tanda hubung):
docker compose up -d

# Jika tetap mau pakai syntax lama, buat alias:
echo "alias docker-compose='docker compose'" >> ~/.bashrc
source ~/.bashrc
```

---

## Logs Terlalu Besar / Disk Penuh

```bash
# Cek ukuran logs
du -sh /var/lib/docker/containers/*/

# Bersihkan logs container yang sudah mati
docker container prune

# Bersihkan semua yang tidak terpakai (image, container, network, build cache)
docker system prune

# Bersihkan termasuk volume yang tidak terpakai (HATI-HATI!)
docker system prune -a --volumes

# Set log limit di docker-compose
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```