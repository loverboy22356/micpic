#!/usr/bin/env bash
# Pull the latest code and restart the MISPEC stack on the Whogohost VPS.
# Run from the backend directory:  bash deploy/whogohost/deploy.sh
set -euo pipefail

APP_DIR=/home/mispec/app
BACKEND_DIR="${APP_DIR}"   # the GitHub repo root is the backend dir
VENV="${APP_DIR}/venv"
SERVICES=(mispec-web mispec-celery mispec-celerybeat)

if [ ! -d "${BACKEND_DIR}" ]; then
  echo "Backend not found at ${BACKEND_DIR}" >&2
  exit 1
fi

cd "${APP_DIR}"

echo "==> Pulling latest code"
git pull --ff-only

echo "==> Installing Python dependencies"
if [ ! -d "${VENV}" ]; then
  python3 -m venv "${VENV}"
fi
"${VENV}/bin/pip" install --upgrade pip wheel
"${VENV}/bin/pip" install -r "${BACKEND_DIR}/requirements.txt"

cd "${BACKEND_DIR}"

echo "==> Applying migrations"
"${VENV}/bin/python" manage.py migrate --noinput

echo "==> Collecting static files"
"${VENV}/bin/python" manage.py collectstatic --noinput

echo "==> Django deployment checks"
"${VENV}/bin/python" manage.py check --deploy || echo "WARNING: check --deploy reported issues (see above)"

echo "==> Restarting services"

if systemctl list-unit-files | grep -q '^mispec-web.service'; then
  # setup-server.sh installs this root-owned helper and a matching sudoers rule,
  # so the app user can restart the stack without a password prompt.
  sudo /usr/local/bin/mispec-restart
  systemctl --no-pager --lines=5 status "${SERVICES[@]}" || true
else
  echo "systemd units not installed yet; skipping restart."
fi

echo "==> Done"
