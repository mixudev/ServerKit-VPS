# Panduan SSL/HTTPS

Panduan lengkap mengaktifkan HTTPS di Docker Server Kit, mencakup dua mode:

| Mode | Tool | Kapan Dipakai |
|------|------|---------------|
| **[A] Local / Simulasi](#mode-a--local--simulasi-mkcert)** | mkcert | VirtualBox, development, testing HTTPS tanpa domain asli |
| **[B] Production](#mode-b--production-lets-encrypt)** | Certbot + Let's Encrypt | VPS production dengan domain asli |

---

## Prasyarat Umum

- Nginx proxy sudah berjalan: `cd /srv/proxy && docker compose up -d`
- Port **80** dan **443** terbuka di firewall:
  ```bash
  sudo ufw allow 80
  sudo ufw allow 443
  sudo ufw status
  ```

---

## Mode A — Local / Simulasi (mkcert)

Gunakan mode ini jika kamu **belum punya domain asli** atau sedang **testing di VirtualBox**.

mkcert membuat Certificate Authority (CA) lokal yang diinstall ke trust store OS/browser.
Sertifikat yang ditandatangani CA ini dipercaya browser — tidak ada warning "Not Secure".

### Cara Kerja

```
[Ubuntu VM]                          [Windows Laptop]
  mkcert generate cert ──────────►
  fullchain.pem + privkey.pem         Import rootCA.pem
  ↓                                   → Windows Certificate Store
  Mount ke Nginx container            → Browser percaya sertifikat ✅
```

### Langkah 1 — Cari IP VM

```bash
# Di Ubuntu VM:
ip addr show
# Cari IP di interface eth0/enp0s3
# Contoh: 192.168.56.101
```

### Langkah 2 — Buat Nginx Config HTTPS

Gunakan flag `--ssl` saat scaffold site baru:

```bash
/srv/new-site.sh nama-site auth.192.168.56.101.nip.io 8000 --ssl
```

Atau edit manual config yang sudah ada di `/srv/proxy/conf.d/nama-site.conf`,
gunakan template dari `/srv/proxy/example.conf.template` (Template A — HTTPS).

### Langkah 3 — Generate Sertifikat

```bash
# Satu domain:
/srv/ssl-local.sh auth.192.168.56.101.nip.io

# Beberapa domain sekaligus:
/srv/ssl-local.sh auth.192.168.56.101.nip.io docs.192.168.56.101.nip.io pma.192.168.56.101.nip.io
```

Script akan:
1. Install mkcert (jika belum ada)
2. Generate sertifikat untuk setiap domain
3. Simpan ke `/srv/proxy/certs/<domain>/`
4. Reload Nginx otomatis

### Langkah 4 — Import CA ke Windows (wajib agar browser percaya)

Script akan menampilkan lokasi file `rootCA.pem`. Copy ke Windows:

```powershell
# Di PowerShell Windows:
scp ubuntu-user@192.168.56.101:/home/ubuntu-user/.local/share/mkcert/rootCA.pem $env:USERPROFILE\Downloads\
```

Lalu install CA ke Windows Certificate Store:

**Cara 1 — Via PowerShell (Administrator):**
```powershell
certutil -addstore -f "ROOT" $env:USERPROFILE\Downloads\rootCA.pem
```

**Cara 2 — Via GUI:**
1. Double-click file `rootCA.pem`
2. Klik **Install Certificate**
3. Pilih **Local Machine** → Next
4. Pilih **Place all certificates in the following store** → Browse
5. Pilih **Trusted Root Certification Authorities** → OK → Next → Finish

### Langkah 5 — Restart Browser & Verifikasi

```bash
# Tutup semua jendela browser, buka ulang
# Buka: https://auth.192.168.56.101.nip.io
# → Harus muncul padlock 🔒 tanpa warning
```

> **Catatan nip.io:** `auth.192.168.56.101.nip.io` secara otomatis resolve ke `192.168.56.101`
> sehingga tidak perlu edit `/etc/hosts`.

### Perbarui Sertifikat

Sertifikat mkcert berlaku **10 tahun** — tidak perlu renewal rutin.
Jika VM di-recreate atau mkcert di-reinstall, jalankan ulang `ssl-local.sh` dan import ulang `rootCA.pem`.

---

## Mode B — Production (Let's Encrypt)

Gunakan mode ini jika kamu sudah punya **domain asli** yang pointing ke IP server.

### Prasyarat Production

- [ ] Domain A record sudah mengarah ke IP server (`dig example.com` harus return IP server)
- [ ] Port 80 dan 443 terbuka di firewall
- [ ] Nginx config untuk domain sudah ada dan menggunakan format HTTPS (Template A)

### Langkah 1 — Verifikasi Domain

```bash
# Cek A record domain sudah benar:
dig example.com +short
# Harus return IP server kamu

# Atau via curl:
curl -I http://example.com
```

### Langkah 2 — Buat Nginx Config HTTPS

```bash
/srv/new-site.sh nama-site example.com 8000 --ssl
```

Kemudian **reload Nginx dalam mode HTTP-only dulu** (sertifikat belum ada):
Sementara hapus dulu block `server { listen 443 ssl; ... }` atau jalankan proxy dengan config HTTP dahulu.

> **Tip:** Jalankan dengan `--staging` dulu untuk testing (tidak kena rate limit):
> ```bash
> /srv/ssl-production.sh example.com admin@example.com --staging
> ```

### Langkah 3 — Issue Sertifikat

```bash
# STAGING dulu (wajib, untuk menghindari rate limit Let's Encrypt):
/srv/ssl-production.sh example.com admin@example.com --staging

# Jika staging berhasil, issue sertifikat asli:
/srv/ssl-production.sh example.com admin@example.com
```

Script akan:
1. Verifikasi domain dapat diakses
2. Jalankan Certbot via Docker (webroot method)
3. Salin sertifikat ke `/srv/proxy/certs/example.com/`
4. Setup cron auto-renewal setiap 12 jam
5. Reload Nginx

### Langkah 4 — Verifikasi

```bash
# Cek sertifikat aktif:
curl -I https://example.com

# Cek grade SSL (harus A atau A+):
# https://www.ssllabs.com/ssltest/analyze.html?d=example.com

# Cek cron renewal terdaftar:
crontab -l | grep ssl-renew

# Cek log renewal:
cat /var/log/certbot-renew.log
```

### Auto-Renewal

Certbot otomatis memperbarui sertifikat yang expire dalam 30 hari.
Cron job berjalan 2x sehari (00:00 dan 12:00):

```bash
# Jalankan renewal manual:
/srv/ssl-renew.sh

# Lihat log:
tail -f /var/log/certbot-renew.log
```

---

## Menambah SSL ke Site yang Sudah Berjalan

Jika site sudah berjalan dalam mode HTTP dan ingin upgrade ke HTTPS:

### 1. Update Nginx Config

Edit `/srv/proxy/conf.d/nama-site.conf`, ubah dari HTTP-only menjadi dual-block HTTPS.
Lihat template di `/srv/proxy/example.conf.template` (Template A).

```nginx
# Ganti config HTTP lama dengan ini:

# Block 1: Redirect
server {
    listen 80;
    server_name example.com;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

# Block 2: HTTPS
server {
    listen 443 ssl;
    server_name example.com;
    ssl_certificate     /etc/nginx/certs/example.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/example.com/privkey.pem;
    include             /etc/nginx/conf.d/ssl-params.conf;
    # ... proxy_pass sama seperti sebelumnya ...
}
```

### 2. Generate Sertifikat

```bash
# Local:
/srv/ssl-local.sh example.com

# Production:
/srv/ssl-production.sh example.com admin@example.com
```

### 3. Reload Nginx

```bash
docker exec nginx-proxy nginx -t   # test config dulu
docker exec nginx-proxy nginx -s reload
```

---

## Struktur Direktori Sertifikat

```
/srv/proxy/certs/
├── auth.example.com/
│   ├── fullchain.pem   ← sertifikat publik
│   └── privkey.pem     ← private key (JANGAN di-share)
├── docs.example.com/
│   ├── fullchain.pem
│   └── privkey.pem
└── live/               ← dibuat oleh Certbot (Let's Encrypt)
    └── example.com/
        ├── fullchain.pem
        └── privkey.pem
```

> **Keamanan:** Direktori `certs/` sudah di-gitignore. Private key tidak pernah masuk ke repository.

---

## Troubleshooting

### ❌ Browser masih "Not Secure" / `ERR_CERT_AUTHORITY_INVALID`

**Penyebab:** rootCA.pem belum diimport ke Windows, atau browser perlu restart.

```bash
# Solusi:
# 1. Pastikan rootCA.pem sudah diimport ke "Trusted Root Certification Authorities"
# 2. Tutup SEMUA jendela browser (bukan hanya tab), buka ulang
# 3. Jika Chrome: chrome://restart untuk restart penuh
```

**Firefox:** Firefox punya trust store sendiri. Import terpisah:
1. Settings → Privacy & Security → Certificates → View Certificates
2. Tab Authorities → Import → pilih `rootCA.pem`
3. Centang "Trust this CA to identify websites"

### ❌ `nginx: [emerg] cannot load certificate`

**Penyebab:** File sertifikat belum ada tapi Nginx config sudah pakai HTTPS.

```bash
# Cek file sertifikat ada:
ls /srv/proxy/certs/<domain>/

# Jika belum ada, generate dulu:
/srv/ssl-local.sh <domain>     # local
/srv/ssl-production.sh <domain> email@example.com  # production

# Lalu reload nginx:
docker exec nginx-proxy nginx -s reload
```

### ❌ Let's Encrypt: `too many certificates` / Rate Limit

**Penyebab:** Terlalu banyak request ke Let's Encrypt (max 5/minggu per domain).

```bash
# Gunakan --staging untuk testing:
/srv/ssl-production.sh example.com admin@example.com --staging
# Sertifikat staging tidak valid di browser, tapi tidak kena rate limit.
# Jika staging berhasil, tunggu 1 minggu atau pakai domain baru untuk production.
```

### ❌ Certbot gagal: `Couldn't connect to server`

**Penyebab:** Domain tidak bisa diakses dari internet via port 80.

```bash
# Cek port 80 terbuka:
sudo ufw status
# Pastikan ada: 80/tcp    ALLOW

# Cek dari luar server (dari laptop):
curl -I http://example.com

# Jika hosting di cloud (AWS, GCP, DO), cek Security Group / Firewall Rules
```

### ❌ mkcert gagal install di Ubuntu

```bash
# Install dependensi manual:
sudo apt-get install -y libnss3-tools

# Download binary langsung:
curl -L https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64 \
     -o /usr/local/bin/mkcert
chmod +x /usr/local/bin/mkcert
mkcert -install
```

---

## Referensi Cepat

```bash
# ---- Local (mkcert) ----
/srv/ssl-local.sh domain.local              # generate cert
/srv/ssl-local.sh d1.local d2.local d3.local  # beberapa domain

# ---- Production (Let's Encrypt) ----
/srv/ssl-production.sh example.com admin@example.com --staging  # test dulu
/srv/ssl-production.sh example.com admin@example.com            # production
/srv/ssl-renew.sh                                               # renewal manual

# ---- Nginx ----
docker exec nginx-proxy nginx -t            # test config
docker exec nginx-proxy nginx -s reload     # reload (zero-downtime)

# ---- Site baru dengan HTTPS ----
/srv/new-site.sh nama domain.com 8000 --ssl

# ---- Cek sertifikat ----
openssl s_client -connect domain.com:443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -dates
```
