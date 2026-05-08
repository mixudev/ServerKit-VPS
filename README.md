# 🐳 Docker Server Kit

Production-ready Docker server infrastructure untuk hosting **multiple websites** di satu VPS/server, menggunakan Nginx sebagai reverse proxy global.

---

## ✨ Fitur

- 🔀 **Nginx Reverse Proxy** — satu pintu masuk untuk semua website
- 🌐 **Multi-site** — hosting banyak website sekaligus, terisolasi satu sama lain
- 📁 **Per-folder per-site** — setiap website punya folder dan lifecycle sendiri
- 🔒 **Network isolation** — database dan service internal tidak bisa diakses dari luar
- ⚡ **Zero-downtime reload** — tambah/ubah site tanpa restart proxy
- 🛠️ **Script helper** — scaffold site baru dengan satu perintah
- 📖 **Dokumentasi lengkap** — panduan CLI, troubleshooting, dan best practice

---

## 📋 Requirements

| Komponen | Minimum | Rekomendasi |
|----------|---------|-------------|
| OS | Ubuntu 20.04 | Ubuntu 22.04 / 24.04 |
| RAM | 1 GB | 2 GB+ |
| Storage | 10 GB | 20 GB+ |
| CPU | 1 core | 2 core+ |
| Akses | sudo | sudo |

---

## 🚀 Quick Start

### 1. Clone repository

```bash
git clone https://github.com/USERNAME/docker-server-kit.git
cd docker-server-kit
```

### 2. Jalankan setup otomatis

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

> Script ini akan install Docker, membuat network global, dan menyiapkan direktori `/srv/`.
> Setelah selesai, **logout dan login ulang** agar permission Docker aktif.

### 3. Jalankan Nginx proxy

```bash
cd /srv/proxy
docker compose up -d
```

### 4. Tambah website pertama

```bash
# Format: ./scripts/new-site.sh <nama-site> <domain> <port-app>
./scripts/new-site.sh my-app myapp.local 8000
```

### 5. Setup domain lokal (tanpa domain asli)

Tambahkan ke `/etc/hosts` di **komputer kamu** (bukan server):

```
192.168.x.x   myapp.local
```

Ganti `192.168.x.x` dengan IP server kamu. Lalu buka `http://myapp.local` di browser.

---

## 📁 Struktur Repository

```
docker-server-kit/
├── proxy/                    # Nginx reverse proxy global
│   ├── docker-compose.yml    # Definisi container proxy
│   ├── nginx.conf            # Konfigurasi utama Nginx
│   └── conf.d/               # Config per-site (*.conf)
│       └── .gitkeep
├── scripts/
│   ├── setup.sh              # Setup awal server (jalankan sekali)
│   ├── new-site.sh           # Scaffold website baru
│   ├── remove-site.sh        # Hapus website
│   └── list-sites.sh         # Lihat semua site yang berjalan
├── docs/
│   ├── installation.md       # Panduan instalasi lengkap
│   ├── cli-reference.md      # Referensi semua perintah CLI
│   ├── adding-sites.md       # Cara tambah berbagai jenis site
│   ├── troubleshooting.md    # Solusi masalah umum
│   └── architecture.md       # Penjelasan arsitektur
├── .gitignore
└── README.md                 # File ini
```

### Struktur di server setelah setup

```
/srv/
├── proxy/                    # Nginx proxy (dari repo ini)
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── conf.d/
│       ├── site-a.conf
│       └── site-b.conf
└── sites/                    # Semua website
    ├── site-a/               # Clone dari repo project
    │   ├── docker-compose.yml
    │   ├── .env              # TIDAK di-commit ke git
    │   └── src/
    └── site-b/
        └── ...
```

---

## 📖 Dokumentasi

| Dokumen | Deskripsi |
|---------|-----------|
| [Instalasi Lengkap](docs/installation.md) | Step-by-step setup dari nol |
| [CLI Reference](docs/cli-reference.md) | Semua perintah yang perlu diketahui |
| [Menambah Site](docs/adding-sites.md) | Template untuk Laravel, FastAPI, Node.js, dll |
| [Troubleshooting](docs/troubleshooting.md) | Solusi masalah umum |
| [Arsitektur](docs/architecture.md) | Penjelasan desain sistem |

---

## ⚡ Cheat Sheet

```bash
# Jalankan proxy
cd /srv/proxy && docker compose up -d

# Tambah site baru
./scripts/new-site.sh nama-site domain.local 8000

# Reload nginx setelah tambah/edit config (zero-downtime)
docker exec nginx-proxy nginx -s reload

# Lihat semua container
docker ps

# Lihat log site tertentu
cd /srv/sites/nama-site && docker compose logs -f

# Stop satu site (tidak hapus data)
cd /srv/sites/nama-site && docker compose down

# Restart satu site
cd /srv/sites/nama-site && docker compose restart

# Masuk ke dalam container
docker exec -it nama-container sh
```

---

## 🏗️ Arsitektur Singkat

```
Browser
   │
   ▼ port 80/443
┌──────────────────┐
│   nginx-proxy    │  ← satu-satunya yang expose port publik
└────────┬─────────┘
         │ routing by domain
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌────────┐
│ site-a │ │ site-b │  ← masing-masing terisolasi
│ nginx  │ │ nginx  │     bisa up/down independent
└────────┘ └────────┘
```

Setiap site terhubung ke dua network:
- `proxy-network` (external) — untuk komunikasi dengan proxy global
- `internal` (per-site) — untuk komunikasi antar container dalam satu site

---

## 🤝 Workflow Menambah Website Baru

```bash
# 1. Scaffold struktur
./scripts/new-site.sh toko-online toko.local 8000

# 2. Clone project ke folder site
cd /srv/sites/toko-online
git clone https://github.com/kamu/toko-online.git src/

# 3. Setup environment
cp src/.env.example .env
nano .env

# 4. Jalankan
docker compose up -d --build

# 5. Reload proxy (zero-downtime)
docker exec nginx-proxy nginx -s reload
```

---

## 📄 License

MIT License — bebas digunakan untuk keperluan personal maupun komersial.