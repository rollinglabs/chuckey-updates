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

# Stop running services
if [ -f "$CHUCKEY_DIR/docker-compose.yml" ]; then
  echo "🛑 Stopping current services using docker-compose..."
  docker compose -f "$CHUCKEY_DIR/docker-compose.yml" down
else
  echo "⚠️ No docker-compose.yml found. Stopping all running containers as fallback..."
  running_containers=$(docker ps -q)
  if [ -n "$running_containers" ]; then
    docker stop $running_containers
    docker rm $running_containers
  else
    echo "✅ No running containers to stop."
  fi
fi

# Replace the current docker-compose.yml with the updated one
echo "📦 Applying updated docker-compose.yml..."
cp "$UPDATE_DIR/docker-compose.yml" "$CHUCKEY_DIR/docker-compose.yml"

# Pull latest images
echo "📥 Pulling latest images..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" pull


# Update version
NEW_VERSION=$(cat "$UPDATE_VERSION_FILE")
echo "$NEW_VERSION" > "$LOCAL_VERSION_FILE"
echo "📝 Updated version to $NEW_VERSION"

# Start updated services
echo "🚀 Starting updated services..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" up -d

echo "✅ Update applied successfully"