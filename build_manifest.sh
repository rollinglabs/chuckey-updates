#!/usr/bin/env bash


set -e

MANIFEST_PATH="./stable/manifest.json"

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

HASH_COMPOSE=$(shasum -a 256 ./stable/docker-compose.yml | awk '{print $1}')
HASH_CHECK=$(shasum -a 256 ./stable/scripts/check_and_fetch.sh | awk '{print $1}')
HASH_UPDATE=$(shasum -a 256 ./stable/scripts/update.sh | awk '{print $1}')
HASH_STATS=$(shasum -a 256 ./stable/scripts/get_stats.sh | awk '{print $1}')
HASH_MONITOR=$(shasum -a 256 ./stable/scripts/update_monitor.sh | awk '{print $1}')
HASH_NETWORK=$(shasum -a 256 ./stable/scripts/network_manager.sh | awk '{print $1}')

cat > ./stable/manifest.json <<EOF
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
  }
}
EOF

echo "✅ Manifest built: stable/manifest.json"