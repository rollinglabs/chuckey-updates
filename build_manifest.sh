#!/bin/bash

set -e

read -p "Version (e.g. v0.9.21): " VERSION
read -p "Release date [Leave empty for now]: " RELEASE_DATE
read -p "Description: " DESCRIPTION
read -p "Requires reboot? (y/N): " REBOOT
read -p "chuckey-ui version: " UI_VERSION
read -p "chuckey-ui description: " UI_DESC
read -p "unifi-controller version: " UNIFI_VERSION
read -p "unifi-controller description: " UNIFI_DESC

if [[ -z "$RELEASE_DATE" ]]; then
  RELEASE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

REBOOT_BOOL=false
[[ "$REBOOT" == "y" || "$REBOOT" == "Y" ]] && REBOOT_BOOL=true

HASH_COMPOSE=$(shasum -a 256 ./stable/docker-compose.yml | awk '{print $1}')
HASH_CHECK=$(shasum -a 256 ./stable/check_and_fetch.sh | awk '{print $1}')
HASH_UPDATE=$(shasum -a 256 ./stable/update.sh | awk '{print $1}')
HASH_STATS=$(shasum -a 256 ./stable/scripts/get_stats.sh | awk '{print $1}')

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
    }
  }
}
EOF

echo "✅ Manifest built: stable/manifest.json"