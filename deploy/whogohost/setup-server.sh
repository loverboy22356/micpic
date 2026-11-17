#!/usr/bin/env bash
# One-time server bootstrap for Ubuntu 22.04/24.04 on a Whogohost Linux VDS/VPS.
# Run as root:  sudo bash setup-server.sh
#
# Installs Python, Nginx, PostgreSQL, Redis and creates the `mispec` user.
# It does NOT touch your repository or .env — run deploy.sh after this.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root (sudo bash setup-server.sh)." >&2
  exit 1
fi

APP_DIR=/home/mispec/app
APP_USER=mispec
DB_NAME=mispec
DB_USER=mispec

echo "==> Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-dev build-essential \
  libpq-dev pkg-config nginx postgresql postgresql-contrib redis-server \
  git curl ufw

echo "==> Ensuring a 2 GB swap file (1-2 GB VPS plans ship without swap)"
if ! swapon --show | grep -q '/swapfile'; then
  if ! fallocate -l 2G /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Swap enabled: $(swapon --show)"
else
  echo "Swap already present, leaving it alone."
fi

echo "==> Creating application user ${APP_USER}"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${APP_USER}"
fi
usermod -aG www-data "${APP_USER}"

echo "==> Allowing ${APP_USER} to restart the app services (nothing else)"
cat > /usr/local/bin/mispec-restart <<'HELPER'
#!/bin/sh
# Installed by deploy/whogohost/setup-server.sh.
# Lets the mispec user restart the three app units without a password.
exec /bin/systemctl restart mispec-web mispec-celery mispec-celerybeat
HELPER
chown root:root /usr/local/bin/mispec-restart
chmod 755 /usr/local/bin/mispec-restart
echo "${APP_USER} ALL=(root) NOPASSWD: /usr/local/bin/mispec-restart" > /etc/sudoers.d/mispec-restart
chmod 440 /etc/sudoers.d/mispec-restart
visudo -c -f /etc/sudoers.d/mispec-restart >/dev/null

if [ ! -d "${APP_DIR}" ]; then
  mkdir -p "${APP_DIR}"
  chown -R "${APP_USER}":"${APP_USER}" "/home/${APP_USER}"
fi
# Nginx needs to traverse the home directory to serve /static and /media.
chmod o+x "/home/${APP_USER}"

echo "==> Creating PostgreSQL role and database"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
  ELSE
    ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;
SQL
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

echo "==> Configuring Redis to listen on loopback only"
sed -i 's/^#\? *bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf
sed -i 's/^#\? *supervised .*/supervised systemd/' /etc/redis/redis.conf
systemctl enable --now redis-server
systemctl restart redis-server

echo "==> Enabling services"
systemctl enable --now postgresql nginx

echo "==> Firewall (SSH, HTTP, HTTPS only)"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
yes | ufw enable || true

cat <<EOF

Server bootstrap finished.

PostgreSQL:
  DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}

Save that password now — it is only printed once. Put it in ${APP_DIR}/.env.

Next steps (see deploy/whogohost/README.md):
  1. git clone <your repo> ${APP_DIR}   (then: chown -R ${APP_USER}:${APP_USER} ${APP_DIR})
  2. sudo -u ${APP_USER} cp ${APP_DIR}/deploy/whogohost/env.example ${APP_DIR}/.env  and fill it in
  3. bash ${APP_DIR}/deploy/whogohost/deploy.sh
  4. Install the nginx site + systemd units from deploy/whogohost/
  5. Run certbot for HTTPS
EOF
