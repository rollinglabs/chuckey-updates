#!/bin/bash

# Define constants
REMOTE_MANIFEST_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/manifest.json"
UPDATE_DIR="/chuckey/update"
LOCAL_VERSION_FILE="/chuckey/VERSION"

FORCE_UPDATE=false
for arg in "$@"; do
  if [ "$arg" = "--force" ]; then
    FORCE_UPDATE=true
    break
  fi
done

mkdir -p "$UPDATE_DIR"

echo "🟡 Checking for update..."

# Skip self-update if just updated
if [ "$CHECK_AND_FETCH_UPDATED" = "1" ]; then
  echo "🛑 Script was just updated. Skipping self-update this run."
  SKIP_SELF_UPDATE=true
fi
# Ensure SKIP_SELF_UPDATE has a default value
: "${SKIP_SELF_UPDATE:=false}"

# Fetch remote version
REMOTE_VERSION=$(curl -H 'Cache-Control: no-cache' -s "$REMOTE_MANIFEST_URL" | jq -r '.version')

# Read local version
if [ -f "$LOCAL_VERSION_FILE" ]; then
  CURRENT_VERSION=$(cat "$LOCAL_VERSION_FILE")
else
  echo "⚠️ No current version found"
  CURRENT_VERSION="unknown"
fi

echo "🧠 Local: $CURRENT_VERSION | Remote: $REMOTE_VERSION"

NEWER_VERSION=$(printf "%s\n%s" "$REMOTE_VERSION" "$CURRENT_VERSION" | sort -V | tail -n1)

FILE_UPDATED=false

if [ "$FORCE_UPDATE" = true ] || { [ "$NEWER_VERSION" = "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; }; then
  echo "⬇️ Update available! Fetching..."
  curl -s -o "$UPDATE_DIR/manifest.json" "$REMOTE_MANIFEST_URL"
  echo "$REMOTE_VERSION" > "$UPDATE_DIR/VERSION"

  # Update scripts and docker-compose.yml
  if command -v jq >/dev/null 2>&1; then
    # Update get_stats.sh if needed
    GET_STATS_PATH=$(jq -r '.files["get_stats.sh"].path' "$UPDATE_DIR/manifest.json")
    if [ -f "$GET_STATS_PATH" ]; then
      EXPECTED_HASH=$(jq -r '.files["get_stats.sh"].sha256' "$UPDATE_DIR/manifest.json")
      CURRENT_HASH=$(sha256sum "$GET_STATS_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
        echo "⬆️ Updating get_stats.sh..."
        curl -s -o "$UPDATE_DIR/get_stats.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/scripts/get_stats.sh"
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/get_stats.sh" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for get_stats.sh. Aborting update."
          exit 1
        fi
        mv "$UPDATE_DIR/get_stats.sh" "$GET_STATS_PATH"
        chmod +x "$GET_STATS_PATH"
        FILE_UPDATED=true
      fi
    fi

    # Update docker-compose.yml
    DOCKER_COMPOSE_PATH=$(jq -r '.files["docker-compose.yml"].path' "$UPDATE_DIR/manifest.json")
    if [ -f "$DOCKER_COMPOSE_PATH" ]; then
      EXPECTED_HASH=$(jq -r '.files["docker-compose.yml"].sha256' "$UPDATE_DIR/manifest.json")
      CURRENT_HASH=$(sha256sum "$DOCKER_COMPOSE_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
        echo "⬆️ Updating docker-compose.yml..."
        curl -s -o "$UPDATE_DIR/docker-compose.yml" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/docker-compose.yml"
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/docker-compose.yml" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for docker-compose.yml. Aborting update."
          exit 1
        fi
        mv "$UPDATE_DIR/docker-compose.yml" "$DOCKER_COMPOSE_PATH"
        FILE_UPDATED=true
      fi
    fi
  fi

  # Execute update
  UPDATE_SH_PATH="/chuckey/scripts/update.sh"
  if [ -f "$UPDATE_SH_PATH" ]; then
    "$UPDATE_SH_PATH"
  else
    echo "⚠️ update.sh not found, manual restart required"
  fi
else
  echo "✅ Already up to date"
fi
