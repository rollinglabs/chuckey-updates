#!/bin/bash
# Chuckey Update Monitor Setup Script
# Run once during hardware burn-in as sudo

set -euo pipefail

echo "🔧 Setting up Chuckey Update Monitor..."

# Install dependencies
echo "📦 Installing inotify-tools..."
apt-get update && apt-get install -y inotify-tools

# Ensure directories exist
mkdir -p /chuckey/scripts
mkdir -p /chuckey/logs
mkdir -p /chuckey/data

# Make sure update_monitor.sh exists and is executable
if [ ! -f "/chuckey/scripts/update_monitor.sh" ]; then
    echo "❌ ERROR: /chuckey/scripts/update_monitor.sh not found!"
    echo "Please create the update_monitor.sh script first."
    exit 1
fi

chmod +x /chuckey/scripts/update_monitor.sh

# Create systemd service
echo "⚙️ Creating systemd service..."
cat > /etc/systemd/system/chuckey-update-monitor.service << 'EOF'
[Unit]
Description=Chuckey Update Monitor
After=network.target docker.service
Wants=network.target

[Service]
Type=simple
ExecStart=/chuckey/scripts/update_monitor.sh
Restart=always
RestartSec=5
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "🚀 Enabling and starting service..."
systemctl daemon-reload
systemctl enable chuckey-update-monitor.service
systemctl start chuckey-update-monitor.service

# Verify status
echo "✅ Checking service status..."
if systemctl is-active --quiet chuckey-update-monitor.service; then
    echo "✅ Chuckey update monitor installed and running successfully!"
    echo "📊 Check status with: sudo systemctl status chuckey-update-monitor.service"
    echo "📝 View logs with: sudo journalctl -u chuckey-update-monitor.service -f"
else
    echo "❌ Service failed to start. Check logs with:"
    echo "   sudo journalctl -u chuckey-update-monitor.service"
    exit 1
fi