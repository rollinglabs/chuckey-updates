#!/bin/sh
#
# OTA Bootstrap Script
#
# Runs inside a one-shot Alpine container to deploy updated OTA scripts
# to field devices that have an outdated check_and_fetch.sh.
#
# This script:
# 1. Reads the update channel (default: stable)
# 2. Downloads the manifest from GitHub
# 3. Compares SHA256 hashes of all OTA-tracked scripts
# 4. Updates any that are outdated or missing
# 5. Creates a trigger file to kick off the new check_and_fetch.sh
#

set -eu

log() { echo "[ota-bootstrap] $1"; }

# Read channel (default: stable)
CHANNEL="stable"
if [ -f "/chuckey/data/update_channel" ]; then
  CHANNEL=$(cat /chuckey/data/update_channel | tr -d '[:space:]')
fi

BASE_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/${CHANNEL}"
MANIFEST_URL="${BASE_URL}/manifest.json"

log "Channel: $CHANNEL"
log "Fetching manifest from $MANIFEST_URL..."

if ! curl -sf -o /tmp/manifest.json "$MANIFEST_URL"; then
  log "Failed to fetch manifest. Network may be unavailable."
  exit 1
fi

UPDATED=false

# Update all OTA-tracked scripts
for file_key in check_and_fetch.sh update.sh update_monitor.sh get_stats.sh network_manager.sh; do
  FILE_PATH=$(jq -r --arg k "$file_key" '.files[$k].path' /tmp/manifest.json)
  EXPECTED_HASH=$(jq -r --arg k "$file_key" '.files[$k].sha256' /tmp/manifest.json)

  # Check current hash (file may not exist on device)
  CURRENT_HASH=""
  if [ -f "$FILE_PATH" ]; then
    CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
  fi

  if [ "$EXPECTED_HASH" = "$CURRENT_HASH" ]; then
    log "$file_key is up to date"
    continue
  fi

  log "Updating $file_key..."
  FILE_URL="${BASE_URL}/scripts/$file_key"

  if ! curl -sf -o "/tmp/$file_key" "$FILE_URL"; then
    log "Failed to download $file_key, skipping"
    continue
  fi

  DL_HASH=$(sha256sum "/tmp/$file_key" | awk '{print $1}')
  if [ "$EXPECTED_HASH" != "$DL_HASH" ]; then
    log "Hash mismatch for $file_key (expected: $EXPECTED_HASH, got: $DL_HASH), skipping"
    continue
  fi

  cp "/tmp/$file_key" "$FILE_PATH"
  chmod +x "$FILE_PATH"
  log "$file_key updated successfully"
  UPDATED=true
done

# Also verify docker-compose.yml
DC_PATH=$(jq -r '.files["docker-compose.yml"].path' /tmp/manifest.json)
DC_EXPECTED=$(jq -r '.files["docker-compose.yml"].sha256' /tmp/manifest.json)
DC_CURRENT=""
if [ -f "$DC_PATH" ]; then
  DC_CURRENT=$(sha256sum "$DC_PATH" | awk '{print $1}')
fi

if [ "$DC_EXPECTED" != "$DC_CURRENT" ]; then
  log "Updating docker-compose.yml..."
  if curl -sf -o "/tmp/docker-compose.yml" "${BASE_URL}/docker-compose.yml"; then
    DL_HASH=$(sha256sum "/tmp/docker-compose.yml" | awk '{print $1}')
    if [ "$DC_EXPECTED" = "$DL_HASH" ]; then
      cp "/tmp/docker-compose.yml" "$DC_PATH"
      log "docker-compose.yml updated"
      UPDATED=true
    fi
  fi
fi

if [ "$UPDATED" = "true" ]; then
  log "Scripts updated. Triggering OTA update cycle..."
  echo "bootstrap" > /chuckey/data/update_apps_immediate
else
  log "All scripts already up to date. No action needed."
fi

log "Bootstrap complete."
