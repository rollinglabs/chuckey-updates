

#!/bin/bash

# Define constants
REMOTE_VERSION_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/VERSION"
REMOTE_MANIFEST_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/manifest.json"
UPDATE_DIR="/chuckey/update"
LOCAL_VERSION_FILE="/app/version"

mkdir -p "$UPDATE_DIR"

echo "🟡 Checking for update..."

# Fetch remote version
REMOTE_VERSION=$(curl -s "$REMOTE_VERSION_URL")
if [ -z "$REMOTE_VERSION" ]; then
  echo "❌ Failed to fetch remote version"
  exit 1
fi

# Read local version
if [ -f "$LOCAL_VERSION_FILE" ]; then
  CURRENT_VERSION=$(cat "$LOCAL_VERSION_FILE")
else
  echo "⚠️ No current version found"
  CURRENT_VERSION="unknown"
fi

echo "🧠 Local: $CURRENT_VERSION | Remote: $REMOTE_VERSION"

if [ "$CURRENT_VERSION" != "$REMOTE_VERSION" ]; then
  echo "⬇️ Update available! Fetching..."
  curl -s -o "$UPDATE_DIR/manifest.json" "$REMOTE_MANIFEST_URL"
  echo "$REMOTE_VERSION" > "$UPDATE_DIR/VERSION"
  echo "✅ Fetched update files"
else
  echo "✅ Already up to date"
fi