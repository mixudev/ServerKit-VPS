# Arsitektur Sistem

Penjelasan lengkap desain dan keputusan arsitektur Docker Server Kit.

---

## Gambaran Besar

```
┌───────────────────────────────────────────────────────┐
│                    Ubuntu Server                     │
│                                                     │
│  Port 80  ──► ┌─────────────────┐  SSL Termination     │
│  Port 443 ──►│   nginx-proxy    │  (HTTPS → HTTP)      │
│           │  /etc/nginx/certs│                       │
│           └────────┬────────┘                       │
│                    │ routing by domain                │
│           proxy-network (Docker bridge)               │
│         ┌──────────┴───────────┐                    │
│         │                      │                    │
│ ┌───────────▼───────┐   ┌───────────▼───────┐        │
│ │   site-a nginx  │   │   site-b nginx  │        │
│ │   (internal)    │   │   (internal)    │        │
│ └────────┬────────┘   └────────┬────────┘        │
│           │ internal-a           │ internal-b       │
│ ┌───────────▼───────┐   ┌───────────▼───────┐        │
│ │  app  db  redis │   │  app  db  redis │        │
│ │  (terisolasi)   │   │  (terisolasi)   │        │
│ └───────────────────┘   └───────────────────┘        │
└───────────────────────────────────────────────────────┘
```

---

## Dua Jenis Network

### 1. `proxy-network` (External / Global)

Network yang dibuat sekali dan digunakan bersama oleh semua site dan proxy global.

```bash
docker network create proxy-network
```

**Container yang terhubung:**
- `nginx-proxy` (global)
- Nginx internal tiap site (atau app yang langsung expose, seperti FastAPI/Node.js)

**Tujuan:** Agar nginx-proxy bisa meneruskan request ke nginx/app masing-masing site.

### 2. `internal` (Per-site / Private)

Network privat yang dibuat otomatis oleh setiap `docker compose` site.

```yaml
networks:
  internal:
    driver: bridge
```

**Container yang terhubung:**
- App (Laravel, FastAPI, dll.)
- Database (MySQL, PostgreSQL)
- Redis
- Worker
- Scheduler
- Dan service internal lainnya

**Tujuan:** Isolasi — database dan service sensitif tidak bisa diakses dari luar container network tersebut.

---

## Kenapa Nginx Internal?

Untuk stack seperti Laravel, diperlukan Nginx internal sebagai "gateway" antara proxy global dan PHP-FPM. Nginx internal ini yang menangani:

- Static files (CSS, JS, gambar)
- PHP-FPM via FastCGI
- URL routing Laravel (`try_files`)
- Storage symlink

```
nginx-proxy ──► nginx-internal ──► php-fpm (app)
                      └──────────► static files
```

Untuk app yang sudah punya built-in HTTP server (FastAPI dengan Uvicorn, Node.js dengan Express), tidak perlu Nginx internal — langsung diteruskan ke container app.

```
nginx-proxy ──► fastapi-app:8000
nginx-proxy ──► nodejs-app:3000
```

---

## Naming Convention Container

Penting untuk memahami bagaimana nama container terbentuk, karena nginx-proxy menggunakan nama container untuk routing.

Docker Compose memberi nama container berdasarkan:
1. Jika ada `name:` di top-level docker-compose.yml → `{name}-{service}`
2. Jika tidak ada `name:` → `{folder}-{service}`

**Contoh:**
```yaml
# /srv/sites/mixuauth/docker-compose.yml
name: mixuauth

services:
  nginx:        # → container name: mixuauth-nginx
  app:          # → container name: mixuauth-app
  db:           # → container name: mixuauth-db
```

Karena itu, nginx proxy config bisa langsung pakai nama container:
```nginx
proxy_pass http://mixuauth-nginx:80;
```

---

## Flow Request (Laravel + HTTPS)

```
1. Browser      → GET https://mixuauth.local
2. DNS/hosts    → resolve ke 192.168.1.100 (IP server)
3. nginx-proxy  → terima di port 443
                   TLS handshake (sertifikat dari /etc/nginx/certs/)
                   server_name mixuauth.local → match
                   proxy_pass http://mixuauth-nginx:80  (HTTP internal)
4. mixuauth-nginx (internal)
                → try_files → /index.php
                → fastcgi_pass app:9000
5. mixuauth-app (PHP-FPM)
                → proses request Laravel
                → return response
6. Response balik ke browser via HTTPS
```

> **SSL Termination di Proxy:** Traffic antara nginx-proxy dan nginx-internal berjalan
> via HTTP di jaringan Docker internal (proxy-network). Ini aman karena Docker network
> tidak bisa diakses dari luar server. Hanya koneksi dari browser ke proxy yang HTTPS.

---

## Isolasi Keamanan

```
Internet
   │
   ▼
nginx-proxy       ← HANYA ini yang terhubung ke internet (port 80/443)
   │
   │ proxy-network
   ▼
nginx-internal    ← terhubung ke proxy-network DAN internal
   │
   │ internal network
   ├──► app       ← tidak bisa diakses dari luar
   ├──► db        ← tidak bisa diakses dari luar
   ├──► redis     ← tidak bisa diakses dari luar
   └──► worker    ← tidak bisa diakses dari luar
```

Database dan Redis hanya ada di network `internal`, sehingga tidak ada cara dari luar server untuk langsung mengakses port database, kecuali melalui app.

---

## Port Binding

Untuk keamanan, port yang di-expose ke host sebaiknya hanya di-bind ke `127.0.0.1`:

```yaml
# AMAN — hanya bisa diakses dari localhost server
ports:
  - "127.0.0.1:3307:3306"   # MySQL untuk dev tools (TablePlus, dll.)
  - "127.0.0.1:6379:6379"   # Redis
  - "127.0.0.1:8081:80"     # phpMyAdmin

# KURANG AMAN — bisa diakses dari semua interface (termasuk internet)
ports:
  - "3307:3306"
  - "6379:6379"
```

Nginx proxy adalah satu-satunya yang boleh bind ke `0.0.0.0` (semua interface):
```yaml
ports:
  - "80:80"
  - "443:443"
```

---

## Satu Sistem Banyak Service

Untuk sistem kompleks seperti mixuauth (Laravel + FastAPI + Worker + Scheduler), semuanya dalam **satu docker-compose.yml**:

```
/srv/sites/mixuauth/
├── docker-compose.yml    ← satu file untuk semua service
├── .env
├── identity-server/      ← source Laravel
├── security-service/     ← source FastAPI
└── docs/                 ← VitePress
```

Hanya Nginx internal yang terhubung ke `proxy-network`. Semua service lain hanya di network `internal`.

Jika FastAPI perlu diakses langsung dari luar (bukan melalui Laravel), buat entry terpisah di nginx proxy:

```nginx
# mixuauth.local → Laravel
server {
    server_name mixuauth.local;
    proxy_pass http://mixuauth-nginx:80;
}

# api.mixuauth.local → FastAPI langsung
server {
    server_name api.mixuauth.local;
    proxy_pass http://mixuauth-fastapi:8000;
}
```

Dan tambahkan FastAPI ke `proxy-network`:
```yaml
fastapi-risk:
  networks:
    - proxy-network   # ← tambahkan ini
    - internal
```