#!/bin/bash
#
# Migration 002: Install chuckey-watchdog.service for power cut recovery
#
# After an ungraceful power loss, Docker's recovery process can internally
# stop containers and set hasBeenManuallyStopped=true in its state DB.
# With restart:unless-stopped, Docker then refuses to restart these containers
# on the next boot — leaving chuckey-ui and other services offline indefinitely.
#
# This migration installs a one-shot systemd service that runs docker compose up -d
# on every boot, ensuring containers are always recovered regardless of Docker's
# internal stopped state.
#

set -euo pipefail

SERVICE_NAME="chuckey-watchdog"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
WATCHDOG_SCRIPT="/chuckey/scripts/chuckey_watchdog.sh"

# Idempotent: skip if already enabled
if systemctl is-enabled "${SERVICE_NAME}.service" >/dev/null 2>&1; then
  echo "[migration-002] ${SERVICE_NAME}.service already enabled, skipping"
  exit 0
fi

# Verify watchdog script exists (delivered by check_and_fetch.sh before migrations run)
if [ ! -f "$WATCHDOG_SCRIPT" ]; then
  echo "[migration-002] $WATCHDOG_SCRIPT not found, cannot install watchdog service"
  exit 1
fi

echo "[migration-002] Installing ${SERVICE_NAME}.service..."

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Chuckey Container Watchdog (power cut recovery)
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/chuckey/scripts/chuckey_watchdog.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl start "${SERVICE_NAME}.service"

echo "[migration-002] ${SERVICE_NAME}.service installed, enabled, and started"
