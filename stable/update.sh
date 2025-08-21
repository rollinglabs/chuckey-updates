#!/bin/bash
set -e

LOG="/chuckey/logs/update.log"
COMPOSE_PATH="/chuckey/update/stable/docker-compose.yml"
VERSION_PATH="/chuckey/update/stable/VERSION"
LOCAL_VERSION_PATH="/chuckey/VERSION"

echo "[$(date)] Starting update to $(cat $VERSION_PATH)..." | tee -a $LOG

docker compose -f "$COMPOSE_PATH" pull | tee -a $LOG
docker compose -f "$COMPOSE_PATH" up -d | tee -a $LOG

cp "$VERSION_PATH" "$LOCAL_VERSION_PATH"

echo "[$(date)] Update complete. Now running $(cat $LOCAL_VERSION_PATH)." | tee -a $LOG