#!/bin/bash
#
# Migration 001: Add chuckey-led.service for LED restore on boot
#
# On Zero2 devices, the LED "netdev" trigger requires runtime sysfs writes
# that are lost on reboot. This service calls led-control.sh normal on boot
# to restore LED normal operation mode.
#

set -euo pipefail

# Idempotent: skip if already enabled
if systemctl is-enabled chuckey-led.service 2>/dev/null; then
  echo "[migration-001] chuckey-led.service already enabled, skipping"
  exit 0
fi

# Check if led-control.sh exists (required for this service)
if [ ! -f /chuckey/scripts/led-control.sh ]; then
  echo "[migration-001] led-control.sh not found, skipping LED service creation"
  exit 0
fi

echo "[migration-001] Creating chuckey-led.service..."

cat > /etc/systemd/system/chuckey-led.service << 'EOF'
[Unit]
Description=Chuckey LED Normal Operation
After=network-online.target chuckey-docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/chuckey/scripts/led-control.sh normal
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable chuckey-led.service
systemctl start chuckey-led.service

echo "[migration-001] chuckey-led.service installed, enabled, and started"
