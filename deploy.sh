#!/usr/bin/env bash
set -euo pipefail

#############################################################
# Deploy Exception Manager (HTTP only)
# - Clones repo
# - Creates python venv
# - Installs backend requirements
# - Inits database
# - Builds frontend
# - Adds systemd service
# - Configures Nginx reverse proxy (HTTP)
#############################################################

APP_REPO="https://github.com/lowrester/ExceptionManager.git"
APP_DIR="/opt/exception-manager"

DB_NAME="exception_manager"
DB_USER="app_user"
DB_PASS="$(openssl rand -base64 20)"

BACKEND_PORT=8000

echo "======================================"
echo "  Deploying Exception Manager"
echo "======================================"

# Checks
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run as root."
  exit 1
fi

echo "[1/7] Creating PostgreSQL database..."

sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}'
   ) THEN
      CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
   END IF;
END
\$do\$;

CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

echo "[2/7] Cloning app into $APP_DIR..."
rm -rf "$APP_DIR" || true
git clone "$APP_REPO" "$APP_DIR"

echo "[3/7] Installing Python backend..."
cd "$APP_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip wheel
pip install gunicorn
pip install -r requirements.txt

echo "[4/7] Creating .env..."
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
SESSION_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

cat > "$APP_DIR/.env" <<EOF
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}
SECRET_KEY=${SECRET_KEY}
SESSION_SECRET=${SESSION_SECRET}
ALLOWED_ORIGINS=http://localhost
UPLOAD_DIR=./uploads
ENVIRONMENT=production
DEBUG=False
EOF

echo "[5/7] Initializing DB (no drop)..."

python3 - <<'EOF'
from app.init_db import initialize_database
initialize_database(drop_existing=False)
EOF

echo "[5/7] Building frontend..."
cd "$APP_DIR/client"
npm install
npm run build

echo "[6/7] Creating systemd service..."

cat > /etc/systemd/system/exception-manager.service <<EOF
[Unit]
Description=Exception Manager Backend
After=network.target postgresql.service

[Service]
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/gunicorn -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:${BACKEND_PORT} app.main:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable exception-manager
systemctl start exception-manager

echo "[7/7] Configuring Nginx reverse proxy..."

cat > /etc/nginx/sites-available/exception-manager <<EOF
server {
    listen 80;

    root ${APP_DIR}/client/dist;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
    }

    client_max_body_size 10M;
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/exception-manager /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

echo
echo "======================================"
echo " Exception Manager installed!"
echo " Frontend:  http://<server-ip>/"
echo " API Docs:  http://<server-ip>/api/docs"
echo "======================================"
