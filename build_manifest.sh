#!/usr/bin/env bash

set -e

# Channel selection (default: stable)
CHANNEL="${1:-stable}"
CHANNEL_DIR="./${CHANNEL}"

if [[ ! -d "$CHANNEL_DIR" ]]; then
  echo "Error: Channel directory '$CHANNEL_DIR' does not exist"
  echo "Usage: $0 [stable|beta]"
  exit 1
fi

MANIFEST_PATH="${CHANNEL_DIR}/manifest.json"

echo "Building manifest for channel: $CHANNEL"
echo ""

# Extract current values if manifest exists
if [[ -f "$MANIFEST_PATH" ]]; then
  CURRENT_VERSION=$(jq -r '.version' "$MANIFEST_PATH")
  CURRENT_DATE=$(jq -r '.release_date' "$MANIFEST_PATH")
  CURRENT_DESC=$(jq -r '.description' "$MANIFEST_PATH")
  CURRENT_REBOOT=$(jq -r '.requires_reboot' "$MANIFEST_PATH")
  CURRENT_UI_VERSION=$(jq -r '.components["chuckey-ui"].version' "$MANIFEST_PATH")
  CURRENT_UI_DESC=$(jq -r '.components["chuckey-ui"].description' "$MANIFEST_PATH")
  CURRENT_UNIFI_VERSION=$(jq -r '.components["unifi-controller"].version' "$MANIFEST_PATH")
  CURRENT_UNIFI_DESC=$(jq -r '.components["unifi-controller"].description' "$MANIFEST_PATH")
fi

read -e -i "$CURRENT_VERSION" -p "Version (e.g. v0.9.21): " VERSION
DEFAULT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
read -e -p "Release date [${DEFAULT_DATE}]: " RELEASE_DATE
RELEASE_DATE=${RELEASE_DATE:-$DEFAULT_DATE}
read -e -i "$CURRENT_DESC" -p "Description: " DESCRIPTION
read -e -p "Requires reboot? (y/[N]): " REBOOT
REBOOT=${REBOOT:-N}
read -e -i "$CURRENT_UI_VERSION" -p "chuckey-ui version: " UI_VERSION
read -e -i "$CURRENT_UI_DESC" -p "chuckey-ui description: " UI_DESC
read -e -i "$CURRENT_UNIFI_VERSION" -p "unifi-controller version: " UNIFI_VERSION
read -e -i "$CURRENT_UNIFI_DESC" -p "unifi-controller description: " UNIFI_DESC

REBOOT_BOOL=false
[[ "$REBOOT" == "y" || "$REBOOT" == "Y" ]] && REBOOT_BOOL=true

# Compute file hashes
HASH_COMPOSE=$(shasum -a 256 "${CHANNEL_DIR}/docker-compose.yml" | awk '{print $1}')
HASH_CHECK=$(shasum -a 256 "${CHANNEL_DIR}/scripts/check_and_fetch.sh" | awk '{print $1}')
HASH_UPDATE=$(shasum -a 256 "${CHANNEL_DIR}/scripts/update.sh" | awk '{print $1}')
HASH_STATS=$(shasum -a 256 "${CHANNEL_DIR}/scripts/get_stats.sh" | awk '{print $1}')
HASH_MONITOR=$(shasum -a 256 "${CHANNEL_DIR}/scripts/update_monitor.sh" | awk '{print $1}')
HASH_NETWORK=$(shasum -a 256 "${CHANNEL_DIR}/scripts/network_manager.sh" | awk '{print $1}')

# Build migrations section (if migrations directory exists)
MIGRATIONS_JSON=""
if [[ -d "${CHANNEL_DIR}/migrations" ]]; then
  MIGRATION_FILES=$(find "${CHANNEL_DIR}/migrations" -name "*.sh" -type f | sort)
  if [[ -n "$MIGRATION_FILES" ]]; then
    MIGRATIONS_JSON=",
  \"migrations\": {"
    FIRST=true
    for mig_file in $MIGRATION_FILES; do
      mig_name=$(basename "$mig_file" .sh)
      mig_hash=$(shasum -a 256 "$mig_file" | awk '{print $1}')

      # Read first comment line as description
      mig_desc=$(grep "^# Migration" "$mig_file" | head -1 | sed 's/^# Migration [0-9]*: //')
      if [[ -z "$mig_desc" ]]; then
        mig_desc="Migration $mig_name"
      fi

      if [[ "$FIRST" != "true" ]]; then
        MIGRATIONS_JSON+=","
      fi
      MIGRATIONS_JSON+="
    \"$mig_name\": {
      \"sha256\": \"$mig_hash\",
      \"description\": \"$mig_desc\"
    }"
      FIRST=false
    done
    MIGRATIONS_JSON+="
  }"
  fi
fi

cat > "$MANIFEST_PATH" <<EOF
{
  "version": "$VERSION",
  "release_date": "$RELEASE_DATE",
  "description": "$DESCRIPTION",
  "requires_reboot": $REBOOT_BOOL,
  "components": {
    "chuckey-ui": {
      "version": "$UI_VERSION",
      "description": "$UI_DESC"
    },
    "unifi-controller": {
      "version": "$UNIFI_VERSION",
      "description": "$UNIFI_DESC"
    }
  },
  "files": {
    "docker-compose.yml": {
      "path": "/chuckey/docker-compose.yml",
      "sha256": "$HASH_COMPOSE"
    },
    "check_and_fetch.sh": {
      "path": "/chuckey/scripts/check_and_fetch.sh",
      "sha256": "$HASH_CHECK"
    },
    "update.sh": {
      "path": "/chuckey/scripts/update.sh",
      "sha256": "$HASH_UPDATE"
    },
    "get_stats.sh": {
      "path": "/chuckey/scripts/get_stats.sh",
      "sha256": "$HASH_STATS"
    },
    "update_monitor.sh": {
      "path": "/chuckey/scripts/update_monitor.sh",
      "sha256": "$HASH_MONITOR"
    },
    "network_manager.sh": {
      "path": "/chuckey/scripts/network_manager.sh",
      "sha256": "$HASH_NETWORK"
    }
  }${MIGRATIONS_JSON}
}
EOF

echo ""
echo "✅ Manifest built: $MANIFEST_PATH"

# Show migrations if any
if [[ -n "$MIGRATIONS_JSON" ]]; then
  echo "   Migrations included:"
  for mig_file in $(find "${CHANNEL_DIR}/migrations" -name "*.sh" -type f | sort); do
    echo "   - $(basename "$mig_file" .sh)"
  done
fi
