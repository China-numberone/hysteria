#!/bin/bash

# Foolproof Hysteria 2 Installation Script for x86_64
# Created for root@r1010093 to resolve Exec format error and set up Hysteria server
# Date: July 09, 2025

# Exit on any error
set -e

# Step 1: Check system architecture
echo "Checking system architecture..."
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: This script is for x86_64 systems only. Your architecture is $ARCH."
    exit 1
fi

# Step 2: Install required tools
echo "Installing required tools (wget, dos2unix, openssl)..."
sudo apt update
sudo apt install -y wget dos2unix openssl

# Step 3: Download Hysteria 2 binary
echo "Downloading Hysteria 2 binary for x86_64..."
sudo rm -f /usr/local/bin/hysteria
wget https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 -O /usr/local/bin/hysteria
sudo chmod +x /usr/local/bin/hysteria

# Verify binary
echo "Verifying Hysteria binary..."
if ! /usr/local/bin/hysteria version; then
    echo "Error: Hysteria binary failed to execute. Please check if the binary is compatible."
    exit 1
fi

# Step 4: Create configuration directory and files
echo "Creating Hysteria configuration directory..."
sudo mkdir -p /etc/hysteria/cert

# Create config.yaml
echo "Creating /etc/hysteria/config.yaml..."
cat << EOF | sudo tee /etc/hysteria/config.yaml
listen: :5678
protocol: udp
auth:
  type: password
  password: x7k9pQzW8mN3vT2rY5
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
tls:
  cert: /etc/hysteria/cert/cert.pem
  key: /etc/hysteria/cert/key.pem
bandwidth:
  up: 100 mbps
  down: 100 mbps
EOF

# Convert config file to Unix format
sudo dos2unix /etc/hysteria/config.yaml

# Step 5: Generate self-signed certificates (if not already present)
if [ ! -f /etc/hysteria/cert/cert.pem ] || [ ! -f /etc/hysteria/cert/key.pem ]; then
    echo "Generating self-signed TLS certificates..."
    sudo openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/cert/key.pem -out /etc/hysteria/cert/cert.pem -days 365 -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=example.com"
    sudo chmod 644 /etc/hysteria/cert/cert.pem
    sudo chmod 600 /etc/hysteria/cert/key.pem
fi

# Step 6: Create systemd service
echo "Creating systemd service for Hysteria..."
cat << EOF | sudo tee /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

# Step 7: Check SELinux status and disable if enforcing
echo "Checking SELinux status..."
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    echo "Disabling SELinux (temporary) to avoid execution issues..."
    sudo setenforce 0
fi

# Step 8: Check for noexec mount and fix
echo "Checking file system mount options..."
if mount | grep /usr/local | grep -q noexec; then
    echo "Removing noexec mount option for /usr/local..."
    sudo mount -o remount,exec /usr/local
fi

# Step 9: Reload systemd and start service
echo "Starting Hysteria service..."
sudo systemctl daemon-reload
sudo systemctl enable hysteria-server
sudo systemctl start hysteria-server

# Step 10: Check service status
echo "Checking Hysteria service status..."
sudo systemctl status hysteria-server --no-pager

# Step 11: Provide user instructions
echo "Hysteria 2 installation complete!"
echo "To check logs: journalctl -u hysteria-server -b"
echo "Config file: /etc/hysteria/config.yaml"
echo "Certificates: /etc/hysteria/cert/cert.pem and /etc/hysteria/cert/key.pem"
echo "Password: x7k9pQzW8mN3vT2rY5 (update /etc/hysteria/config.yaml if needed)"
echo "If the service fails, check logs with 'journalctl -u hysteria-server -b'."