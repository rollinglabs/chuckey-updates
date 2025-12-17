#!/bin/bash

# Define key paths
UPDATE_DIR="/chuckey/update"
CHUCKEY_DIR="/chuckey"
LOCAL_VERSION_FILE="$CHUCKEY_DIR/VERSION"
UPDATE_VERSION_FILE="$UPDATE_DIR/VERSION"

echo "🛠️ Applying update..."

#
# Check if required docker-compose.yml exists in the expected location
if [ ! -f "$CHUCKEY_DIR/docker-compose.yml" ]; then
  echo "❌ docker-compose.yml not found at expected location: $CHUCKEY_DIR/docker-compose.yml"
  exit 1
fi

if [ ! -f "$UPDATE_VERSION_FILE" ]; then
  echo "❌ Missing VERSION file in update folder"
  exit 1
fi

# Pull latest images
echo "📥 Pulling latest images..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" pull

# Update version
NEW_VERSION=$(cat "$UPDATE_VERSION_FILE")
echo "$NEW_VERSION" > "$LOCAL_VERSION_FILE"
echo "📝 Updated version to $NEW_VERSION"

# Stop and remove existing containers to avoid docker-compose 1.29.2 ContainerConfig bug
# This bug occurs when recreating containers with newer Docker images that don't have ContainerConfig
echo "🛑 Stopping existing containers..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" down --remove-orphans 2>/dev/null || true

# Start updated services with fresh containers
echo "🚀 Starting updated services..."
docker compose -f "$CHUCKEY_DIR/docker-compose.yml" up -d

echo "✅ Update applied successfully"