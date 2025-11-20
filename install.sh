#!/usr/bin/env bash
set -euo pipefail

#############################################################
#  Debian Base Installer for Proxmox
#  - Installs Python3, Node 20, PostgreSQL, Nginx, Git
#############################################################

echo "======================================"
echo "   Debian Base Installation (No SSL)"
echo "======================================"
echo

# Check OS
if ! grep -qi "debian" /etc/os-release && ! grep -qi "ubuntu" /etc/os-release; then
  echo "ERROR: This script only supports Debian/Ubuntu."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run as root (sudo)."
  exit 1
fi

echo "[1/6] Updating system..."
apt update -y && apt upgrade -y

echo "[2/6] Installing system packages..."
apt install -y \
  git curl sudo build-essential \
  python3 python3-venv python3-pip \
  postgresql postgresql-contrib \
  nginx ca-certificates gnupg lsb-release

echo "[3/6] Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "[4/6] Enabling PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

echo "[5/6] Enabling Nginx..."
systemctl enable nginx
systemctl start nginx

echo "[6/6] Cleaning..."
apt autoremove -y

echo
echo "======================================"
echo "  Base installation complete!"
echo "  Next: run deploy.sh"
echo "======================================"
