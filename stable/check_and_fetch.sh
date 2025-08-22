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
        echo "♻️ Updating check_and_fetch.sh..."
        curl -s -o "$CHECK_AND_FETCH_PATH" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/check_and_fetch.sh"
        EXPECTED_HASH=$(jq -r '.files["check_and_fetch.sh"].sha256' "$UPDATE_DIR/manifest.json")
        DOWNLOADED_HASH=$(sha256sum "$CHECK_AND_FETCH_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for check_and_fetch.sh. Aborting update."
          exit 1
        fi
        chmod +x "$CHECK_AND_FETCH_PATH"
        echo "🔁 Restarting to apply updated check_and_fetch.sh..."
        export CHECK_AND_FETCH_UPDATED=1
        exec "$0"
      fi

      UPDATE_SH_PATH=$(jq -r '.files["update.sh"].path' "$UPDATE_DIR/manifest.json")
      if [ -f "$UPDATE_SH_PATH" ]; then
        echo "♻️ Updating update.sh..."
        curl -s -o "$UPDATE_SH_PATH" "https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/update.sh"
        EXPECTED_HASH=$(jq -r '.files["update.sh"].sha256' "$UPDATE_DIR/manifest.json")
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_SH_PATH" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for update.sh. Aborting update."
          exit 1
        fi
        chmod +x "$UPDATE_SH_PATH"
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