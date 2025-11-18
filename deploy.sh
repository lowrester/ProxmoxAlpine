#!/bin/bash
set -e

echo "=============================="
echo "   Exception Manager Installer"
echo "=============================="

REPO_URL="https://github.com/YOURNAME/YOURREPO.git"
APP_DIR="/opt/exception-manager"
DB_USER="app_user"
DB_PASS="ChangeThisPassword"
DB_NAME="exception_manager"

echo "[1/9] Updating system..."
sudo apt update -y && sudo apt upgrade -y

echo "[2/9] Installing dependencies (Python, Git, Nginx)..."
sudo apt install -y python3 python3-venv python3-pip git nginx curl build-essential

echo "[3/9] Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

echo "[4/9] Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

echo "[5/9] Setting up PostgreSQL..."
sudo -u postgres psql <<EOF
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF

echo "[6/9] Cloning repository..."
sudo rm -rf $APP_DIR || true
sudo git clone $REPO_URL $APP_DIR

echo "[7/9] Setting up Python backend..."
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "[*] Creating .env file..."
SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
SESSION=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

cat <<EOF | sudo tee $APP_DIR/.env
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}
SECRET_KEY=$SECRET
SESSION_SECRET=$SESSION
ALLOWED_ORIGINS=http://localhost
UPLOAD_DIR=./uploads
ENVIRONMENT=production
DEBUG=False
EOF

echo "[8/9] Building frontend..."
cd $APP_DIR/client
npm install
npm run build

echo "[*] Configuring NGINX..."
sudo tee /etc/nginx/sites-available/exception_manager >/dev/null <<EOF
server {
    listen 80;

    root $APP_DIR/client/dist;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/exception_manager /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

echo "[*] Creating systemd service..."
sudo tee /etc/systemd/system/exception_manager.service >/dev/null <<EOF
[Unit]
Description=Exception Manager Backend
After=network.target postgresql.service

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/gunicorn -k uvicorn.workers.UvicornWorker app.main:app --bind 0.0.0.0:8000
Restart=always
EnvironmentFile=$APP_DIR/.env

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable exception_manager
sudo systemctl start exception_manager

echo "=============================="
echo "   Deployment COMPLETE!"
echo "=============================="
echo "Frontend: http://<server-ip>"
echo "Backend:  http://<server-ip>/api"
