# Panduan Instalasi Lengkap

Dokumen ini menjelaskan cara setup Docker Server Kit dari nol di Ubuntu Server.

---

## Persiapan VirtualBox (Jika Pakai Local Lab)

Sebelum setup, pastikan network adapter VirtualBox dikonfigurasi dengan benar.

### Setting Network VirtualBox

1. Matikan VM (Powered Off, bukan Saved State)
2. Buka **Settings** → **Network**
3. Pilih **Adapter 1** → ubah dari NAT ke **Bridged Adapter**
4. Pilih network interface komputer kamu (biasanya nama WiFi/LAN kamu)
5. Klik OK, nyalakan VM

> **Kenapa Bridged?** Dengan Bridged Adapter, VM mendapat IP sendiri di jaringan lokalmu (misal `192.168.1.100`), sehingga bisa diakses dari komputer host dan perangkat lain di jaringan yang sama. Dengan NAT, VM hanya bisa diakses dari komputer host via port forwarding yang rumit.

### Cek IP VM

Setelah VM menyala:

```bash
ip addr show
# Cari IP di interface eth0 atau enp0s3
# Contoh: 192.168.1.100
```

Catat IP ini — akan digunakan untuk setup `/etc/hosts`.

---

## Instalasi

### Step 1 — Clone Repository di Server

SSH masuk ke server terlebih dahulu:

```bash
ssh user@192.168.1.100
```

Lalu clone repository:

```bash
# Install git jika belum ada
sudo apt-get install -y git

# Clone repository
git clone https://github.com/USERNAME/docker-server-kit.git
cd docker-server-kit
```

### Step 2 — Jalankan Setup

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Script ini melakukan:
- Install Docker Engine & Docker Compose Plugin
- Tambahkan user ke group `docker` (tidak perlu `sudo` setiap pakai docker)
- Buat Docker network global `proxy-network`
- Salin file ke `/srv/proxy/`
- Salin scripts helper ke `/srv/`

### Step 3 — Relogin

Setelah setup selesai, **wajib logout dan login ulang** agar permission group docker aktif:

```bash
exit
# Login lagi:
ssh user@192.168.1.100

# Verifikasi docker bisa dijalankan tanpa sudo:
docker ps
```

### Step 4 — Jalankan Nginx Proxy

```bash
cd /srv/proxy
docker compose up -d

# Verifikasi:
docker ps | grep nginx-proxy
```

Nginx proxy sekarang berjalan dan listen di port 80.

---

## Setup Domain Lokal (Tanpa Beli Domain)

Edit file `/etc/hosts` di **komputer kamu** (bukan di server):

### Windows

Buka **Notepad sebagai Administrator**, lalu buka file:
```
C:\Windows\System32\drivers\etc\hosts
```

### Mac / Linux

```bash
sudo nano /etc/hosts
```

### Tambahkan baris berikut

```
# Docker Server Kit - Local Development
192.168.1.100   site-a.local
192.168.1.100   site-b.local
192.168.1.100   api.local
```

Ganti `192.168.1.100` dengan IP server kamu.

> **Catatan:** Perubahan `/etc/hosts` hanya berlaku di komputer tersebut. Jika ingin akses dari HP atau perangkat lain, edit juga `/etc/hosts` di perangkat tersebut, atau setup DNS lokal (seperti Pi-hole).

---

## Menambah Website Pertama

```bash
# Format: /srv/new-site.sh <nama-site> <domain> <port>
/srv/new-site.sh hello-world hello.local 3000

# Edit docker-compose sesuai stack kamu
nano /srv/sites/hello-world/docker-compose.yml

# Jalankan
cd /srv/sites/hello-world
docker compose up -d --build

# Reload nginx
docker exec nginx-proxy nginx -s reload
```

Buka browser: `http://hello.local`

---

## Verifikasi Instalasi

```bash
# Cek semua container
docker ps

# Cek network
docker network ls | grep proxy

# Cek status sites
/srv/list-sites.sh

# Test nginx config
docker exec nginx-proxy nginx -t
```

---

## Uninstall

Jika ingin menghapus semua:

```bash
# Stop dan hapus semua container
cd /srv/proxy && docker compose down
for site in /srv/sites/*/; do
    cd "$site" && docker compose down -v
done

# Hapus network
docker network rm proxy-network

# Hapus direktori
sudo rm -rf /srv/

# Uninstall Docker (opsional)
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /etc/docker
```