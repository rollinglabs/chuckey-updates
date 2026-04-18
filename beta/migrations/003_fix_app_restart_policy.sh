#!/bin/bash
#
# Migration 003: Fix restart policy for installed app containers
#
# Beta.3 updated core containers (chuckey-ui, unifi-controller) to restart:always
# but apps-compose.yml (managed separately) was left with restart:unless-stopped.
# After a power cut, Docker's recovery can set hasBeenManuallyStopped=true on
# containers, which prevents restart:unless-stopped from recovering them on reboot.
#
# This migration patches apps-compose.yml to use restart:always and force-recreates
# affected containers so the new policy takes effect immediately.
#

set -euo pipefail

APPS_COMPOSE="/chuckey/data/apps-compose.yml"
MAIN_COMPOSE="/chuckey/docker-compose.yml"

# Skip if no apps-compose.yml (no apps installed)
if [ ! -f "$APPS_COMPOSE" ]; then
  echo "[migration-003] No apps-compose.yml found, nothing to do"
  exit 0
fi

# Idempotent: skip if already patched (no unless-stopped remaining)
if ! grep -q 'restart: unless-stopped' "$APPS_COMPOSE"; then
  echo "[migration-003] apps-compose.yml already uses restart:always, skipping"
  exit 0
fi

echo "[migration-003] Patching apps-compose.yml: unless-stopped -> always..."
sed -i 's/restart: unless-stopped/restart: always/g' "$APPS_COMPOSE"

# Force-recreate app containers so Docker picks up the new restart policy.
# A running container's restart policy only changes when the container is recreated.
echo "[migration-003] Recreating app containers to apply new restart policy..."
COMPOSE_CMD="docker compose -f $MAIN_COMPOSE -f $APPS_COMPOSE"
APP_SERVICES=$(docker compose -f "$APPS_COMPOSE" config --services 2>/dev/null || true)

if [ -z "$APP_SERVICES" ]; then
  echo "[migration-003] No app services found, skipping container recreation"
  exit 0
fi

for service in $APP_SERVICES; do
  echo "[migration-003] Recreating $service..."
  docker stop "$service" 2>/dev/null || true
  docker rm "$service" 2>/dev/null || true
  if $COMPOSE_CMD up -d "$service" 2>&1; then
    echo "[migration-003] $service recreated successfully"
  else
    echo "[migration-003] WARNING: failed to recreate $service"
  fi
done

echo "[migration-003] App restart policies updated"
