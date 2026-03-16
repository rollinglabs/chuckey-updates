#!/bin/bash
#
# chuckey_watchdog.sh — Boot-time container recovery
#
# Ensures all Chuckey compose services are running after boot.
# Handles the case where Docker's restart policy fails to recover
# containers after an ungraceful shutdown (power cut, kernel panic),
# which can leave containers stopped with hasBeenManuallyStopped=true.
#
# Called by chuckey-watchdog.service on every boot.
#

CHUCKEY_DIR="/chuckey"
APPS_COMPOSE="$CHUCKEY_DIR/data/apps-compose.yml"
LOG_TAG="chuckey-watchdog"

COMPOSE_CMD="docker compose -f $CHUCKEY_DIR/docker-compose.yml"
if [ -f "$APPS_COMPOSE" ]; then
  COMPOSE_CMD="$COMPOSE_CMD -f $APPS_COMPOSE"
fi

# Wait up to 30s for Docker daemon to be ready
for i in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker info >/dev/null 2>&1; then
  echo "[$LOG_TAG] Docker not ready after 30s, skipping"
  exit 1
fi

# Bring up any stopped or missing containers
echo "[$LOG_TAG] Ensuring containers are running..."
$COMPOSE_CMD up -d 2>&1 | sed "s/^/[$LOG_TAG] /"

echo "[$LOG_TAG] Container check complete"
