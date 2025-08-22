#!/bin/bash

# Define key paths
UPDATE_DIR="/chuckey/update"
CHUCKEY_DIR="/chuckey"
LOCAL_VERSION_FILE="$CHUCKEY_DIR/VERSION"
UPDATE_VERSION_FILE="$UPDATE_DIR/VERSION"

echo "🛠️ Applying update..."

# Check if required update files exist
if [ ! -f "$UPDATE_DIR/docker-compose.yml" ]; then
  echo "❌ Missing docker-compose.yml in update folder"
  exit 1
fi

if [ ! -f "$UPDATE_VERSION_FILE" ]; then
  echo "❌ Missing VERSION file in update folder"
  exit 1
fi

# Stop running services if docker-compose.yml exists
if [ -f "$CHUCKEY_DIR/docker-compose.yml" ]; then
  echo "🛑 Stopping current services..."
  docker compose -f "$CHUCKEY_DIR/docker-compose.yml" down
else
  echo "⚠️ No existing docker-compose.yml found, skipping shutdown"
fi

# Replace the current docker-compose.yml with the updated one
echo "📦 Applying updated docker-compose.yml..."
cp "$UPDATE_DIR/docker-compose.yml" "$CHUCKEY_DIR/docker-compose.yml"

# Ensure previous container is fully removed to avoid conflict
if docker ps -a --format '{{.Names}}' | grep -Eq '^chuckey-ui$'; then
  echo "🧹 Removing existing chuckey-ui container..."
  docker rm -f chuckey-ui
fi

# Update version
NEW_VERSION=$(cat "$UPDATE_VERSION_FILE")
echo "$NEW_VERSION" > "$LOCAL_VERSION_FILE"
echo "📝 Updated version to $NEW_VERSION"


# Start updated services
echo "🚀 Starting updated services..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" up -d

# Optional: update supporting scripts if present in the update package
for script in check_and_fetch.sh update.sh; do
  if [ -f "$UPDATE_DIR/$script" ]; then
    echo "🔁 Updating $script..."
    cp "$UPDATE_DIR/$script" "$CHUCKEY_DIR/$script"
    chmod +x "$CHUCKEY_DIR/$script"
  fi
done

echo "✅ Update applied successfully"