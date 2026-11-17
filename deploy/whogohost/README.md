# Hosting the MISPEC backend on Whogohost

> Need to justify the plan choice to the account owner? Send them `OWNER_EXPLAINER.md` in this folder — it explains, without jargon, why the existing ₦8,600/month Flex plan cannot run this API and what the options cost.

## First: which Whogohost product you need

| Whogohost product | Works for this backend? | Why |
|---|---|---|
| Shared hosting (DirectAdmin) — the plan with "WordPress Management" / "Site Builder" in the dashboard | ❌ No | No Python app server, no root, MySQL only (no Postgres), no Redis, no long-running Celery workers |
| Python Hosting (Flex ₦8,600/mo, Flex-Max ₦11,000/mo) | ❌ No | Advertises Django/Flask, but it is still DirectAdmin shared hosting: MySQL only, no Redis, and no persistent Celery worker/beat daemon |
| **Linux VPS — C2 Server (₦18,275/mo, 2 GB RAM) or C3 (₦25,500/mo, 2 vCore/2 GB)** | ✅ Yes, recommended | Full root + SSH: Gunicorn + Nginx + PostgreSQL + Redis + Celery |
| Linux VPS C1 (₦11,050/mo, 1 GB RAM) | ⚠️ Barely | Gunicorn + Postgres + Redis + 2 Celery processes will swap constantly; only with the swap file below and low traffic |
| Linux VDS (from ₦100,440/mo) | ✅ Yes, overkill | Dedicated-resource servers; far more than this app needs |
| Windows VPS | ⚠️ Possible | You would run everything as Windows services; the scripts here assume Linux |

Buy path in the Whogohost client area: **Products → VPS Hosting → choose a plan → OS: Ubuntu 22.04 LTS** (or 24.04). Provisioning is instant; you get an email with the server IPv4 and root password.

This backend is a Django 5 + DRF app that also needs **PostgreSQL**, **Redis** and **three long-running processes**:

- `gunicorn mispec.wsgi:application` — the HTTP API
- `celery -A mispec worker -Q celery,geocoding_queue` — background jobs (geocoding, emails)
- `celery -A mispec beat` — scheduled jobs (daily plan check, monthly call reset)

Only a VPS/VDS gives you that. Everything below assumes **Ubuntu 22.04 or 24.04 with root SSH access**.

---

## Step 0 — Order the VPS (the click path)

1. Log in at whogohost.com, then in the top menu choose **Server → VPS Hosting** (direct link: <https://whogohost.com/hosting/vps/>).
2. On the **C2 Server** card (₦18,275/mo — 1 vCore, 2 GB ECC RAM, 50 GB SSD, 1 static IPv4), click **Choose Plan**. C2 is the realistic minimum; C1 (1 GB) only survives with the swap file below and light traffic.
3. In the cart/checkout, configure:
   - **Operating system:** Ubuntu 22.04 LTS 64-bit (24.04 also works). Do **not** pick a preinstalled LAMP/LEMP image — those spread the stack onto Apache/PHP.
   - **Billing cycle:** monthly is fine; longer cycles usually show a lower per-month rate.
   - **Hostname:** e.g. `api.mispec.co.uk` (cosmetic, changeable later).
   - **Backups:** optional add-on; the nightly `pg_dump` cron in this doc covers the database either way.
4. Pay in Naira (card / Paystack / bank transfer). The VPS plans are **self-managed** — you own OS updates, backups and uptime.
5. Provisioning is instant. You receive an email with the **IPv4 address** and **root password**, and the server shows up in your client area with a web console and root-password reset option.

## Step 1 — Point a domain at the VPS

1. In your DNS (Whogohost **DNS Management**, or Cloudflare if the domain is there), create:

   ```
   A    api.mispec.co.uk    ->  <VPS IPv4>
   ```

2. Wait for propagation, then confirm: `ping api.mispec.co.uk`.

> If the domain is behind Cloudflare, set the record to **DNS only (grey cloud)** until the certificate is issued, then you can proxy it.

## Step 1b — Push the deploy kit to GitHub first

The server clones from GitHub (`github.com/loverboy22356/micpic`), so this folder and the `settings.py` changes must exist on the remote **before** you SSH in. On your laptop, in `backend/`:

```bash
git add .gitignore mispec/settings.py deploy
git commit -m "Add Whogohost VPS deployment kit and proxy-safe settings"
git push -u origin deploy
```

If the GitHub repo is private, the clone on the server will ask for a username and password: use your GitHub username and a **personal access token** (fine-grained, read-only Contents) as the password — GitHub passwords do not work for git.

## Step 2 — Log in and bootstrap the server

```bash
ssh root@<VPS IPv4>
apt-get update && apt-get install -y git
git clone -b deploy https://github.com/loverboy22356/micpic.git /home/mispec/app
```

(Cloning as root is fine here — the next commands fix ownership. If the clone reports "dubious ownership" later, see Troubleshooting.)

Run the bootstrap script:

```bash
cd /home/mispec/app/backend/deploy/whogohost
bash setup-server.sh
```

It installs Python 3, Nginx, PostgreSQL, Redis, the `mispec` system user, creates the database, binds Redis to loopback, and enables the firewall (22/80/443). **It prints the generated database password once — save it.**

Then fix ownership and switch to the app user:

```bash
chown -R mispec:mispec /home/mispec
su - mispec
```

## Step 3 — Configure the environment

```bash
cd /home/mispec/app/backend
cp deploy/whogohost/env.example .env
nano .env
```

Fill in every value. The important ones for a VPS install:

```env
SECRET_KEY=<long random string: python3 -c "import secrets;print(secrets.token_urlsafe(50))">
DEBUG=False
ALLOWED_HOSTS=api.mispec.co.uk
CSRF_TRUSTED_ORIGINS=https://api.mispec.co.uk
DATABASE_URL=postgres://mispec:<password from setup>@127.0.0.1:5432/mispec
REDIS_URL=redis://127.0.0.1:6379/0
GOOGLE_SERVICE_ACCOUNT_FILE=firebase/mispec-firebase-adminsdk.json
```

Notes:

- `python-decouple` reads `.env` from the backend folder automatically, so systemd does not need an `EnvironmentFile`.
- The Pusher credentials are read as **`app_id`, `key`, `secret`, `cluster`** (lowercase) by `mispec/settings.py`. Use those exact names.
- Upload the Firebase service-account JSON to the server (e.g. `/home/mispec/app/backend/firebase/mispec-firebase-adminsdk.json`). Do **not** commit it. If the path does not exist, Firebase simply is not initialised.
- Uploads go to **Cloudinary** (`DEFAULT_FILE_STORAGE`), so no media volume is required.

## Step 4 — First deploy

```bash
cd /home/mispec/app/backend
bash deploy/whogohost/deploy.sh
```

This creates the virtualenv, installs `requirements.txt`, runs migrations, collects static files and runs `manage.py check --deploy`.

Create the admin user and a cache table check:

```bash
/home/mispec/app/venv/bin/python manage.py createsuperuser
curl -s http://127.0.0.1:8000/api/api.json/ -o /dev/null -w "%{http_code}\n"   # after step 5
```

## Step 5 — Install the systemd services

**Run this as root** — type `exit` to leave the `mispec` shell you entered in Step 3.

```bash
sudo cp /home/mispec/app/backend/deploy/whogohost/mispec-web.service        /etc/systemd/system/
sudo cp /home/mispec/app/backend/deploy/whogohost/mispec-celery.service      /etc/systemd/system/
sudo cp /home/mispec/app/backend/deploy/whogohost/mispec-celerybeat.service  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mispec-web mispec-celery mispec-celerybeat
sudo systemctl status mispec-web --no-pager
sudo journalctl -u mispec-web -n 40 --no-pager
```

Gunicorn binds `127.0.0.1:8000` only — nothing is public yet.

> `mispec-celerybeat` must run as **exactly one** instance; two beat processes will fire duplicate scheduled tasks.

## Step 6 — Nginx + HTTPS

Still as **root**.

```bash
sudo cp /home/mispec/app/backend/deploy/whogohost/nginx-mispec.conf /etc/nginx/sites-available/mispec.conf
sudo nano /etc/nginx/sites-available/mispec.conf      # set server_name to your real domain
sudo ln -s /etc/nginx/sites-available/mispec.conf /etc/nginx/sites-enabled/mispec.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.mispec.co.uk --redirect
```

Then verify from your laptop:

```bash
curl -I https://api.mispec.co.uk/api/api.json/        # expect 200
```

- Swagger UI: `https://api.mispec.co.uk/`
- Django admin: `https://api.mispec.co.uk/admin/` (login must work — that proves `CSRF_TRUSTED_ORIGINS` is right)

## Step 7 — Point the Flutter app at the new API

Update the API base URL in `frontend/` (currently it points at the Render deployment, `https://mispec.onrender.com` in `backend/test_all_apis.py`). Anything on Android/iOS must use `https://` — cleartext HTTP is blocked by default.

---

## Day-to-day: deploying a change

```bash
ssh mispec@<VPS IP>
cd /home/mispec/app
bash backend/deploy/whogohost/deploy.sh
```

That script does `git pull`, reinstalls requirements, migrates, collects static, and restarts all three services.

Useful commands:

```bash
sudo systemctl restart mispec-web             # only the API
sudo journalctl -u mispec-celery -f           # watch background jobs
sudo journalctl -u mispec-web -n 100 --no-pager
sudo tail -f /var/log/nginx/mispec.error.log
```

## Database backups

```bash
# Manual dump
sudo -u postgres pg_dump mispec | gzip > ~/mispec-$(date +%F).sql.gz
```

Add a nightly cron (as root):

```cron
0 2 * * * su - postgres -c 'pg_dump mispec' | gzip > /home/mispec/backups/mispec-$(date +\%F).sql.gz
```

Keep the last 7: `find /home/mispec/backups -name 'mispec-*.sql.gz' -mtime +7 -delete`.
For off-server copies, push those dumps to object storage (Cloudinary is only for media, not backups).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `502 Bad Gateway` from Nginx | Gunicorn is down: `sudo journalctl -u mispec-web -n 50`. Usually a missing `.env` value or a failed migration. |
| `DisallowedHost` | `ALLOWED_HOSTS` in `.env` does not include the domain; restart `mispec-web` after editing. |
| `403 CSRF verification failed` on `/admin/` | `CSRF_TRUSTED_ORIGINS` missing the `https://` entry. |
| Admin CSS missing | `collectstatic` not run or Nginx `/static/` alias/permissions wrong (`chmod o+x /home/mispec`). |
| Celery tasks never run | `REDIS_URL` wrong, or the worker service is stopped: `sudo journalctl -u mispec-celery -n 50`. |
| Emails not sent | `GMAIL_USER` / `GMAIL_APP_PASSWORD` / `BREVO_API_KEY` empty in `.env`. |
| Tasks run twice | Two `mispec-celerybeat` processes — keep only one. |
| `fatal: could not read Username for 'https://github.com'` | Private repo: use a personal access token as the password, or make the repo public. |
| `detected dubious ownership in repository` | Repo owned by root: `chown -R mispec:mispec /home/mispec` then `sudo -u mispec git config --global --add safe.directory /home/mispec/app`. |
| `git pull --ff-only` fails on the server | Local edits exist on the server (`/home/mispec/app`); discard them with `git -C /home/mispec/app checkout -- .` — never edit code on the server. |

## Repo changes this deployment needed

`backend/mispec/settings.py` was adjusted so the app works behind Nginx and with a local (non-TLS) Redis:

- `SECURE_PROXY_SSL_HEADER` + `USE_X_FORWARDED_HOST` so Django knows the request is HTTPS.
- `CSRF_TRUSTED_ORIGINS` (env-driven) so the admin/Swagger POSTs work over HTTPS.
- Celery SSL options are now applied **only** when `REDIS_URL` starts with `rediss://`; previously the hard-coded SSL options made a plain `redis://127.0.0.1:6379/0` connection fail.

`setup-server.sh` also installs `/usr/local/bin/mispec-restart` plus a `sudoers.d` rule for it, so the unprivileged `mispec` user can restart the three app units during `deploy.sh` without a password prompt (and without being granted unrestricted sudo).

Files in this folder: `setup-server.sh`, `deploy.sh`, `gunicorn.conf.py`, `nginx-mispec.conf`, `mispec-web.service`, `mispec-celery.service`, `mispec-celerybeat.service`, `env.example`.
