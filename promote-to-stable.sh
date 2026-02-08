#!/usr/bin/env bash
#
# Promote beta channel to stable
#
# Copies all scripts, migrations, and docker-compose.yml from beta/ to stable/,
# then rebuilds the stable manifest with updated hashes.
#
# Usage: ./promote-to-stable.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Promoting beta → stable..."
echo ""

# Verify beta channel exists
if [[ ! -d "beta" ]]; then
  echo "Error: beta/ directory not found"
  exit 1
fi

# Copy scripts
echo "Copying scripts..."
cp beta/scripts/check_and_fetch.sh stable/scripts/
cp beta/scripts/update.sh stable/scripts/
cp beta/scripts/update_monitor.sh stable/scripts/
cp beta/scripts/get_stats.sh stable/scripts/
cp beta/scripts/network_manager.sh stable/scripts/

# Copy bootstrap script if it exists
if [[ -f "beta/scripts/ota_bootstrap.sh" ]]; then
  cp beta/scripts/ota_bootstrap.sh stable/scripts/
fi

# Copy docker-compose.yml
echo "Copying docker-compose.yml..."
cp beta/docker-compose.yml stable/

# Copy migrations
if [[ -d "beta/migrations" ]]; then
  echo "Copying migrations..."
  mkdir -p stable/migrations
  cp -r beta/migrations/*.sh stable/migrations/ 2>/dev/null || true
fi

echo ""
echo "Files synced. Now run build_manifest.sh to rebuild the stable manifest:"
echo "  ./build_manifest.sh stable"
echo ""
echo "Then update the docker-compose.yml bootstrap URL from 'beta' to 'stable':"
echo "  sed -i '' 's|/beta/scripts/ota_bootstrap.sh|/stable/scripts/ota_bootstrap.sh|' stable/docker-compose.yml"
echo ""
echo "Finally, commit and push to deploy to field devices."
