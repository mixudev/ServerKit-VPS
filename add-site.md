# Menambah Website Baru

Panduan ini berisi template siap pakai untuk berbagai stack teknologi.

---

## Alur Umum

```bash
# 1. Scaffold struktur folder
/srv/new-site.sh nama-site domain.local PORT

# 2. Ganti docker-compose.yml sesuai stack
nano /srv/sites/nama-site/docker-compose.yml

# 3. Isi .env
nano /srv/sites/nama-site/.env

# 4. Jalankan
cd /srv/sites/nama-site
docker compose up -d --build

# 5. Reload proxy (zero-downtime)
docker exec nginx-proxy nginx -s reload
```

---

## Template: Laravel (Stack Lengkap)

Stack: PHP-FPM + Nginx Internal + MySQL + Redis + Queue Worker + Scheduler

### docker-compose.yml

```yaml
name: nama-site

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: nama-site-app
    restart: unless-stopped
    command: >
      sh -c "
        chmod 660 /var/www/html/storage/oauth-private.key 2>/dev/null || true &&
        chmod 660 /var/www/html/storage/oauth-public.key 2>/dev/null || true &&
        php-fpm
      "
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    env_file: .env
    volumes:
      - ./src:/var/www/html
      - vendor_data:/var/www/html/vendor
    networks:
      - internal

  nginx:
    image: nginx:alpine
    container_name: nama-site-nginx
    restart: unless-stopped
    depends_on:
      - app
    volumes:
      - ./src:/var/www/html:ro
      - ./docker/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    expose:
      - "80"              # tidak expose ke host, cukup ke proxy
    networks:
      - proxy-network     # ← terhubung ke proxy global
      - internal

  worker:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: nama-site-worker
    restart: unless-stopped
    command: php artisan queue:work redis --queue=high,default --tries=3
    depends_on:
      - app
      - redis
    env_file: .env
    volumes:
      - ./src:/var/www/html
      - vendor_data:/var/www/html/vendor
    networks:
      - internal

  scheduler:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: nama-site-scheduler
    restart: unless-stopped
    command: sh -c "while true; do php artisan schedule:run --verbose && sleep 60; done"
    depends_on:
      - app
      - db
    env_file: .env
    volumes:
      - ./src:/var/www/html
      - vendor_data:/var/www/html/vendor
    networks:
      - internal

  db:
    image: mysql:8.0
    container_name: nama-site-db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${DB_DATABASE}
      MYSQL_USER: ${DB_USERNAME}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - internal          # ← TIDAK di proxy-network, aman dari luar
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    container_name: nama-site-redis
    restart: unless-stopped
    command: redis-server --requirepass "${REDIS_PASSWORD}"
    volumes:
      - redis_data:/data
    networks:
      - internal
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

volumes:
  db_data:
  redis_data:
  vendor_data:

networks:
  proxy-network:
    external: true
  internal:
    driver: bridge
```

### Dockerfile

```dockerfile
FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
    curl git zip unzip \
    libpng-dev libjpeg-dev libwebp-dev \
    oniguruma-dev libxml2-dev \
    && docker-php-ext-install \
        pdo pdo_mysql mbstring exif pcntl bcmath gd opcache

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

EXPOSE 9000
CMD ["php-fpm"]
```

### docker/nginx.conf (Nginx Internal)

```nginx
server {
    listen 80;
    server_name localhost;
    root /var/www/html/public;
    index index.php;

    server_tokens off;
    real_ip_header X-Forwarded-For;
    set_real_ip_from 0.0.0.0/0;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location /storage {
        alias /var/www/html/storage/app/public;
        access_log off;
        expires max;
    }

    location ~ \.php$ {
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for;
        fastcgi_param HTTP_X_REAL_IP $remote_addr;
        include fastcgi_params;
        fastcgi_read_timeout 60;
    }

    location ~ /\. { deny all; }
}
```

### Nginx Proxy Config (/srv/proxy/conf.d/nama-site.conf)

```nginx
server {
    listen 80;
    server_name nama-site.local;

    location / {
        proxy_pass         http://nama-site-nginx:80;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
```

### .env

```env
APP_NAME=NamaSite
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://nama-site.local

DB_CONNECTION=mysql
DB_HOST=nama-site-db
DB_PORT=3306
DB_DATABASE=nama_site_db
DB_USERNAME=nama_site_user
DB_PASSWORD=password_kuat_disini

MYSQL_ROOT_PASSWORD=root_password_kuat

CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

REDIS_HOST=nama-site-redis
REDIS_PASSWORD=redis_password_kuat
REDIS_PORT=6379
```

---

## Template: FastAPI / Python

Stack: FastAPI + Uvicorn + PostgreSQL

### docker-compose.yml

```yaml
name: nama-api

services:
  app:
    build: .
    container_name: nama-api-app
    restart: unless-stopped
    volumes:
      - ./src:/app
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    networks:
      - proxy-network     # langsung ke proxy, tanpa nginx internal
      - internal

  db:
    image: postgres:16-alpine
    container_name: nama-api-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db_data:

networks:
  proxy-network:
    external: true
  internal:
    driver: bridge
```

### Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Nginx Proxy Config

```nginx
server {
    listen 80;
    server_name api.local;

    location / {
        proxy_pass         http://nama-api-app:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
```

---

## Template: Node.js / Express

Stack: Node.js + Express + MySQL

### docker-compose.yml

```yaml
name: nama-node

services:
  app:
    build: .
    container_name: nama-node-app
    restart: unless-stopped
    volumes:
      - ./src:/app
      - /app/node_modules
    env_file: .env
    depends_on:
      - db
    networks:
      - proxy-network
      - internal

  db:
    image: mysql:8.0
    container_name: nama-node-db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${DB_DATABASE}
      MYSQL_USER: ${DB_USERNAME}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - internal

volumes:
  db_data:

networks:
  proxy-network:
    external: true
  internal:
    driver: bridge
```

### Dockerfile

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY src/package*.json ./
RUN npm install --production

COPY src/ .

EXPOSE 3000
CMD ["node", "index.js"]
```

---

## Tips: Sistem dengan Banyak Service (seperti mixuauth)

Jika satu sistem punya banyak service (Laravel + FastAPI + Worker + Scheduler), gunakan satu `docker-compose.yml` untuk semua service dalam satu sistem. Hanya **Nginx internal** yang perlu terhubung ke `proxy-network`. Service lain (DB, Redis, Worker) cukup di network `internal`.

```yaml
# Yang terhubung ke proxy-network: hanya nginx
nginx:
  networks:
    - proxy-network   # ← terhubung ke proxy global
    - internal

# Yang TIDAK perlu terhubung ke proxy-network:
db:
  networks:
    - internal        # ← hanya internal, lebih aman

redis:
  networks:
    - internal

worker:
  networks:
    - internal

fastapi:
  networks:
    - internal        # FastAPI diakses via Laravel, bukan dari luar langsung
```