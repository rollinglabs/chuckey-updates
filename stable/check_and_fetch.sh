#!/bin/bash

# Define constants
REMOTE_MANIFEST_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/manifest.json"
UPDATE_DIR="/chuckey/update"
LOCAL_VERSION_FILE="/chuckey/VERSION"

mkdir -p "$UPDATE_DIR"


echo "🟡 Checking for update..."

# Skip self-update if just updated
if [ "$CHECK_AND_FETCH_UPDATED" = "1" ]; then
  echo "🛑 Script was just updated. Skipping self-update this run."
  SKIP_SELF_UPDATE=true
fi

# Fetch remote version
REMOTE_VERSION=$(curl -s "$REMOTE_MANIFEST_URL" | jq -r '.version')

# Read local version
if [ -f "$LOCAL_VERSION_FILE" ]; then
  CURRENT_VERSION=$(cat "$LOCAL_VERSION_FILE")
else
  echo "⚠️ No current version found"
  CURRENT_VERSION="unknown"
fi

echo "🧠 Local: $CURRENT_VERSION | Remote: $REMOTE_VERSION"

NEWER_VERSION=$(printf "%s\n%s" "$REMOTE_VERSION" "$CURRENT_VERSION" | sort -V | tail -n1)

if [ "$NEWER_VERSION" = "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
  echo "⬇️ Update available! Fetching..."
  curl -s -o "$UPDATE_DIR/manifest.json" "$REMOTE_MANIFEST_URL"
  echo "$REMOTE_VERSION" > "$UPDATE_DIR/VERSION"
  # Optional: update this script or others if present in manifest
  if [ "$SKIP_SELF_UPDATE" != "true" ]; then
    if command -v jq >/dev/null 2>&1; then
      CHECK_AND_FETCH_PATH=$(jq -r '.files["check_and_fetch.sh"].path' "$UPDATE_DIR/manifest.json")
      if [ -f "$CHECK_AND_FETCH_PATH" ]; then
        EXPECTED_HASH=$(jq -r '.files["check_and_fetch.sh"].sha256' "$UPDATE_DIR/manifest.json")
        CURRENT_HASH=$(sha256sum "$CHECK_AND_FETCH_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
          echo "♻️ Updating check_and_fetch.sh..."
          curl -s -o "$UPDATE_DIR/check_and_fetch.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/check_and_fetch.sh"
          DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/check_and_fetch.sh" | awk '{print $1}')
          if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
            echo "❌ Hash mismatch for check_and_fetch.sh. Aborting update."
            exit 1
          fi
          mv "$UPDATE_DIR/check_and_fetch.sh" "$CHECK_AND_FETCH_PATH"
          chmod +x "$CHECK_AND_FETCH_PATH"
          echo "🔁 Restarting to apply updated check_and_fetch.sh..."
          export CHECK_AND_FETCH_UPDATED=1
          exec "$0"
        else
          echo "✅ check_and_fetch.sh is up to date"
        fi
      fi

      UPDATE_SH_PATH=$(jq -r '.files["update.sh"].path' "$UPDATE_DIR/manifest.json")
      if [ -f "$UPDATE_SH_PATH" ]; then
        EXPECTED_HASH=$(jq -r '.files["update.sh"].sha256' "$UPDATE_DIR/manifest.json")
        CURRENT_HASH=$(sha256sum "$UPDATE_SH_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
          echo "⬆️ Updating update.sh..."
          curl -s -o "$UPDATE_DIR/update.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/update.sh"
          DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/update.sh" | awk '{print $1}')
          if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
            echo "❌ Hash mismatch for update.sh. Aborting update."
            exit 1
          fi
          mv "$UPDATE_DIR/update.sh" "$UPDATE_SH_PATH"
          chmod +x "$UPDATE_SH_PATH"
        else
          echo "✅ update.sh is up to date"
        fi
      fi

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
        else
          echo "✅ docker-compose.yml is up to date"
        fi
      fi

      GET_STATS_PATH=$(jq -r '.files["get_stats.sh"].path' "$UPDATE_DIR/manifest.json")
      if [ -f "$GET_STATS_PATH" ]; then
        EXPECTED_HASH=$(jq -r '.files["get_stats.sh"].sha256' "$UPDATE_DIR/manifest.json")
        CURRENT_HASH=$(sha256sum "$GET_STATS_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
          echo "⬆️ Updating get_stats.sh..."
          curl -s -o "$UPDATE_DIR/get_stats.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/get_stats.sh"
          DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/get_stats.sh" | awk '{print $1}')
          if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
            echo "❌ Hash mismatch for get_stats.sh. Aborting update."
            exit 1
          fi
          mv "$UPDATE_DIR/get_stats.sh" "$GET_STATS_PATH"
          chmod +x "$GET_STATS_PATH"
        else
          echo "✅ get_stats.sh is up to date"
        fi
      fi
    else
      echo "⚠️ jq not found, skipping self-update of scripts"
    fi
  fi
  echo "✅ Fetched update files"
  /chuckey/update/update.sh
else
  echo "✅ Already up to date"
fi