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
  # Optional: update this script or others if present in manifest
  if [ "$SKIP_SELF_UPDATE" != "true" ]; then
    if command -v jq >/dev/null 2>&1; then
      CHECK_AND_FETCH_PATH=$(jq -r '.files["check_and_fetch.sh"].path' "$UPDATE_DIR/manifest.json")
      echo "🔍 Verifying check_and_fetch.sh at: $CHECK_AND_FETCH_PATH"
      if [ -f "$CHECK_AND_FETCH_PATH" ]; then
        EXPECTED_HASH=$(jq -r '.files["check_and_fetch.sh"].sha256' "$UPDATE_DIR/manifest.json")
        CURRENT_HASH=$(sha256sum "$CHECK_AND_FETCH_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
          echo "♻️ Updating check_and_fetch.sh..."
          curl -s -o "$UPDATE_DIR/check_and_fetch.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/scripts/check_and_fetch.sh"
          DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/check_and_fetch.sh" | awk '{print $1}')
          if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
            echo "❌ Hash mismatch for check_and_fetch.sh. Aborting update."
            exit 1
          fi
          mv "$UPDATE_DIR/check_and_fetch.sh" "$CHECK_AND_FETCH_PATH"
          chmod +x "$CHECK_AND_FETCH_PATH"
          FILE_UPDATED=true
          echo "🔁 Restarting to apply updated check_and_fetch.sh..."
          export CHECK_AND_FETCH_UPDATED=1
          exec "$0"
        else
          echo "✅ check_and_fetch.sh is up to date"
        fi
      fi
    else
      echo "⚠️ jq not found, skipping self-update of scripts"
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    UPDATE_SH_PATH=$(jq -r '.files["update.sh"].path' "$UPDATE_DIR/manifest.json")
    echo "🔍 Verifying update.sh at: $UPDATE_SH_PATH"
    if [ -f "$UPDATE_SH_PATH" ]; then
      EXPECTED_HASH=$(jq -r '.files["update.sh"].sha256' "$UPDATE_DIR/manifest.json")
      CURRENT_HASH=$(sha256sum "$UPDATE_SH_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
        echo "⬆️ Updating update.sh..."
        curl -s -o "$UPDATE_DIR/update.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/scripts/update.sh"
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/update.sh" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for update.sh. Aborting update."
          exit 1
        fi
        mv "$UPDATE_DIR/update.sh" "$UPDATE_SH_PATH"
        chmod +x "$UPDATE_SH_PATH"
        FILE_UPDATED=true
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
        FILE_UPDATED=true
      else
        echo "🔍 Verifying docker-compose.yml at: $DOCKER_COMPOSE_PATH"
        echo "✅ docker-compose.yml is up to date"
      fi
      # Ensure docker-compose.yml exists at its destination location before running update.sh
      if [ -z "$DOCKER_COMPOSE_PATH" ] || [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        echo "❌ docker-compose.yml not found at expected location: $DOCKER_COMPOSE_PATH"
        exit 1
      fi
    fi

    GET_STATS_PATH=$(jq -r '.files["get_stats.sh"].path' "$UPDATE_DIR/manifest.json")
    echo "🔍 Verifying get_stats.sh at: $GET_STATS_PATH"
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
      else
        echo "✅ get_stats.sh is up to date"
      fi
    fi

    UPDATE_MONITOR_PATH=$(jq -r '.files["update_monitor.sh"].path' "$UPDATE_DIR/manifest.json")
    echo "🔍 Verifying update_monitor.sh at: $UPDATE_MONITOR_PATH"
    if [ -f "$UPDATE_MONITOR_PATH" ]; then
      EXPECTED_HASH=$(jq -r '.files["update_monitor.sh"].sha256' "$UPDATE_DIR/manifest.json")
      CURRENT_HASH=$(sha256sum "$UPDATE_MONITOR_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
        echo "⬆️ Updating update_monitor.sh..."
        curl -s -o "$UPDATE_DIR/update_monitor.sh" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/scripts/update_monitor.sh"
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/update_monitor.sh" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for update_monitor.sh. Aborting update."
          exit 1
        fi
        mv "$UPDATE_DIR/update_monitor.sh" "$UPDATE_MONITOR_PATH"
        chmod +x "$UPDATE_MONITOR_PATH"
        FILE_UPDATED=true
        echo "🔄 Restarting update monitor service..."
        systemctl restart chuckey-update-monitor
      else
        echo "✅ update_monitor.sh is up to date"
      fi
    fi
  else
    echo "⚠️ jq not found, skipping update of other scripts"
  fi

  # Print fetched/updated message and call update.sh
  if [ "$FILE_UPDATED" = true ]; then
    echo "✅ Fetched and updated files"
  else
    echo "✅ All files already up to date"
  fi

  if [ "$FORCE_UPDATE" = true ]; then
    echo "🚨 Force flag detected: re-applying all files in manifest"
    for file_key in $(jq -r '.files | keys[]' "$UPDATE_DIR/manifest.json"); do
      file_url="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/${file_key}"
      dest_path=$(jq -r --arg k "$file_key" '.files[$k].path' "$UPDATE_DIR/manifest.json")
      echo "🔁 Forcing update of $file_key to $dest_path"
      curl -s -o "$dest_path" "$file_url"
      chmod +x "$dest_path" 2>/dev/null || true
    done
  fi

  UPDATE_SH_PATH=$(jq -r '.files["update.sh"].path' "$UPDATE_DIR/manifest.json")
  "$UPDATE_SH_PATH"
else
  echo "✅ Already up to date"
fi