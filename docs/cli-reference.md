# CLI Reference

Referensi lengkap semua perintah yang perlu diketahui.

---

## Scripts Bawaan

```bash
# Setup server baru (jalankan sekali)
./scripts/setup.sh

# Tambah website baru
/srv/new-site.sh <nama-site> <domain> <port>

# Hapus website
/srv/remove-site.sh <nama-site>
/srv/remove-site.sh <nama-site> --delete-data   # hapus data juga

# Lihat status semua site
/srv/list-sites.sh
```

---

## Docker Compose

Semua perintah dijalankan dari dalam folder site (`/srv/sites/nama-site/`).

```bash
# Jalankan semua service
docker compose up -d

# Jalankan dan rebuild image (setelah ubah Dockerfile/kode)
docker compose up -d --build

# Hentikan semua service (data volume aman)
docker compose down

# Hentikan dan hapus volume (data hilang!)
docker compose down -v

# Restart semua service
docker compose restart

# Restart satu service saja
docker compose restart app

# Lihat status service
docker compose ps

# Lihat log semua service (realtime)
docker compose logs -f

# Lihat log satu service saja
docker compose logs -f app
docker compose logs -f db

# Lihat 100 baris terakhir log
docker compose logs --tail=100 app

# Scale service (jalankan 3 instance)
docker compose up -d --scale app=3

# Pull image terbaru
docker compose pull

# Rebuild tanpa cache
docker compose build --no-cache
```

---

## Docker Container

```bash
# Lihat semua container yang berjalan
docker ps

# Lihat semua container (termasuk yang mati)
docker ps -a

# Masuk ke shell container
docker exec -it nama-container sh       # Alpine/Alpine-based
docker exec -it nama-container bash     # Debian/Ubuntu-based

# Masuk sebagai root
docker exec -it -u root nama-container sh

# Jalankan perintah di dalam container
docker exec nama-container php artisan migrate
docker exec nama-container python manage.py shell
docker exec nama-container npm run build

# Lihat log container
docker logs nama-container
docker logs -f nama-container           # realtime
docker logs --tail=50 nama-container    # 50 baris terakhir

# Copy file dari/ke container
docker cp nama-container:/app/file.txt ./file.txt
docker cp ./file.txt nama-container:/app/file.txt

# Inspect detail container (IP, network, env, dll.)
docker inspect nama-container

# Lihat resource usage realtime
docker stats
docker stats --no-stream               # snapshot sekali
```

---

## Nginx Proxy

```bash
# Reload config (zero-downtime, setelah tambah/edit .conf)
docker exec nginx-proxy nginx -s reload

# Test config (sebelum reload, pastikan tidak ada error)
docker exec nginx-proxy nginx -t

# Restart Nginx proxy (jika reload tidak cukup)
docker compose -f /srv/proxy/docker-compose.yml restart

# Lihat access log
docker exec nginx-proxy tail -f /var/log/nginx/access.log

# Lihat error log
docker exec nginx-proxy tail -f /var/log/nginx/error.log

# Lihat log site tertentu (jika diset di .conf)
docker exec nginx-proxy tail -f /var/log/nginx/nama-site.access.log
```

---

## Docker Network

```bash
# Lihat semua network
docker network ls

# Inspect network (lihat container yang terhubung)
docker network inspect proxy-network

# Lihat IP container dalam network
docker network inspect proxy-network --format \
  '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'

# Buat network baru (sudah dilakukan oleh setup.sh)
docker network create proxy-network

# Sambungkan container ke network
docker network connect proxy-network nama-container

# Putuskan container dari network
docker network disconnect proxy-network nama-container
```

---

## Docker Volume

```bash
# Lihat semua volume
docker volume ls

# Inspect volume (lihat mount point)
docker volume inspect nama-volume

# Hapus volume yang tidak terpakai
docker volume prune

# Backup volume ke tar
docker run --rm \
  -v nama-volume:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/backup.tar.gz -C /data .

# Restore volume dari tar
docker run --rm \
  -v nama-volume:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/backup.tar.gz -C /data
```

---

## Laravel Spesifik

```bash
# Masuk ke container app
docker exec -it nama-site-app sh

# Artisan commands
docker exec nama-site-app php artisan migrate
docker exec nama-site-app php artisan migrate:fresh --seed
docker exec nama-site-app php artisan cache:clear
docker exec nama-site-app php artisan config:clear
docker exec nama-site-app php artisan route:clear
docker exec nama-site-app php artisan queue:restart
docker exec nama-site-app php artisan key:generate
docker exec nama-site-app php artisan storage:link

# Composer
docker exec nama-site-app composer install
docker exec nama-site-app composer update
docker exec nama-site-app composer dump-autoload

# Masuk ke MySQL
docker exec -it nama-site-db mysql -u root -p
docker exec -it nama-site-db mysql -u laravel_user -p laravel_db

# Masuk ke Redis CLI
docker exec -it nama-site-redis redis-cli -a password
```

---

## FastAPI / Python Spesifik

```bash
# Masuk ke container
docker exec -it nama-site-app bash

# Install package baru
docker exec nama-site-app pip install nama-package

# Jalankan migration Alembic
docker exec nama-site-app alembic upgrade head

# Masuk ke PostgreSQL
docker exec -it nama-site-db psql -U fastapi_user -d fastapi_db
```

---

## Node.js Spesifik

```bash
# Masuk ke container
docker exec -it nama-site-app sh

# npm commands
docker exec nama-site-app npm install
docker exec nama-site-app npm run build
docker exec nama-site-app npm run test
```

---

## Nano Editor (Quick Reference)

```
Ctrl+O       Simpan file
Enter        Konfirmasi nama file saat simpan
Ctrl+X       Keluar
Ctrl+K       Cut (potong) satu baris
Ctrl+U       Paste
Ctrl+W       Cari teks
Ctrl+\       Cari dan ganti
Ctrl+G       Tampilkan bantuan
Alt+U        Undo
```

---

## Vim Editor (Quick Reference)

```
i            Masuk mode edit (insert)
Esc          Keluar mode edit
:w           Simpan
:q           Keluar
:wq          Simpan dan keluar
:q!          Keluar tanpa simpan
/kata        Cari "kata"
n            Cari berikutnya
dd           Hapus satu baris
yy           Copy satu baris
p            Paste
u            Undo
Ctrl+R       Redo
gg           Ke baris pertama
G            Ke baris terakhir
:NomorBaris  Ke baris tertentu (contoh: :42)
```

---

## System & Networking

```bash
# Cek IP server
hostname -I
ip addr show

# Cek port yang sedang digunakan
sudo ss -tlnp
sudo netstat -tlnp          # jika netstat terinstall

# Cek disk usage
df -h
du -sh /srv/sites/*

# Cek memory
free -h

# Cek CPU
top
htop                        # jika htop terinstall

# Monitor semua container realtime
watch -n 2 docker ps
```