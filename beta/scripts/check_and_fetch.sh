#!/bin/bash

# Define constants
UPDATE_DIR="/chuckey/update"
LOCAL_VERSION_FILE="/chuckey/VERSION"

# Channel detection: read from /chuckey/data/update_channel (default: stable)
CHANNEL="stable"
if [ -f "/chuckey/data/update_channel" ]; then
  CHANNEL=$(cat /chuckey/data/update_channel | tr -d '[:space:]')
fi
REMOTE_BASE_URL="https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/${CHANNEL}"
REMOTE_MANIFEST_URL="${REMOTE_BASE_URL}/manifest.json"

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

  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq not found, cannot process manifest"
    exit 1
  fi

  # Handle self-update of check_and_fetch.sh first (with restart)
  if [ "$SKIP_SELF_UPDATE" != "true" ]; then
    CHECK_AND_FETCH_PATH=$(jq -r '.files["check_and_fetch.sh"].path' "$UPDATE_DIR/manifest.json")
    if [ -f "$CHECK_AND_FETCH_PATH" ]; then
      EXPECTED_HASH=$(jq -r '.files["check_and_fetch.sh"].sha256' "$UPDATE_DIR/manifest.json")
      CURRENT_HASH=$(sha256sum "$CHECK_AND_FETCH_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
        echo "♻️ Updating check_and_fetch.sh..."
        curl -s -o "$UPDATE_DIR/check_and_fetch.sh" "${REMOTE_BASE_URL}/scripts/check_and_fetch.sh"
        DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/check_and_fetch.sh" | awk '{print $1}')
        if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
          echo "❌ Hash mismatch for check_and_fetch.sh. Aborting update."
          exit 1
        fi
        mv "$UPDATE_DIR/check_and_fetch.sh" "$CHECK_AND_FETCH_PATH"
        chmod +x "$CHECK_AND_FETCH_PATH"
        echo "🔁 Restarting to apply updated check_and_fetch.sh..."
        export CHECK_AND_FETCH_UPDATED=1
        exec "$0"
      else
        echo "✅ check_and_fetch.sh is up to date"
      fi
    fi
  fi

  # Loop through ALL files in manifest and update if needed
  for file_key in $(jq -r '.files | keys[]' "$UPDATE_DIR/manifest.json"); do
    # Skip check_and_fetch.sh (already handled above)
    if [ "$file_key" = "check_and_fetch.sh" ]; then
      continue
    fi

    # Get file path and expected hash from manifest
    FILE_PATH=$(jq -r --arg k "$file_key" '.files[$k].path' "$UPDATE_DIR/manifest.json")
    EXPECTED_HASH=$(jq -r --arg k "$file_key" '.files[$k].sha256' "$UPDATE_DIR/manifest.json")

    echo "🔍 Verifying $file_key at: $FILE_PATH"

    # Check if file exists and compare hash
    if [ -f "$FILE_PATH" ]; then
      CURRENT_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
      if [ "$EXPECTED_HASH" = "$CURRENT_HASH" ]; then
        echo "✅ $file_key is up to date"
        continue
      fi
    else
      echo "⚠️ $file_key not found, will download"
    fi

    # File needs updating
    echo "⬆️ Updating $file_key..."

    # Determine the correct URL based on file type
    if [[ "$file_key" == *.sh ]]; then
      FILE_URL="${REMOTE_BASE_URL}/scripts/$file_key"
    else
      FILE_URL="${REMOTE_BASE_URL}/$file_key"
    fi

    # Download to update directory first
    curl -s -o "$UPDATE_DIR/$file_key" "$FILE_URL"

    # Verify downloaded file hash
    DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/$file_key" | awk '{print $1}')
    if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
      echo "❌ Hash mismatch for $file_key. Aborting update."
      exit 1
    fi

    # Move to final location
    mv "$UPDATE_DIR/$file_key" "$FILE_PATH"

    # Make scripts executable
    if [[ "$file_key" == *.sh ]]; then
      chmod +x "$FILE_PATH"
    fi

    FILE_UPDATED=true

    # Special handling for update_monitor.sh - restart service
    if [ "$file_key" = "update_monitor.sh" ]; then
      echo "🔄 Restarting update monitor service..."
      systemctl restart chuckey-update-monitor 2>/dev/null || echo "⚠️ Could not restart update monitor (may not be root)"
    fi
  done

  # Print completion message
  if [ "$FILE_UPDATED" = true ]; then
    echo "✅ Fetched and updated files"
  else
    echo "✅ All files already up to date"
  fi

  # Run migrations (if manifest has a migrations section)
  if jq -e '.migrations' "$UPDATE_DIR/manifest.json" >/dev/null 2>&1; then
    echo "🔄 Checking migrations..."
    MIGRATIONS_STATE="/chuckey/data/migrations_completed.json"
    if [ ! -f "$MIGRATIONS_STATE" ]; then
      echo '{}' > "$MIGRATIONS_STATE"
    fi

    for migration_key in $(jq -r '.migrations | keys[]' "$UPDATE_DIR/manifest.json" | sort); do
      # Check if already applied
      if jq -e --arg k "$migration_key" '.[$k]' "$MIGRATIONS_STATE" >/dev/null 2>&1; then
        echo "✅ Migration $migration_key already applied"
        continue
      fi

      # Download and verify migration script
      EXPECTED_HASH=$(jq -r --arg k "$migration_key" '.migrations[$k].sha256' "$UPDATE_DIR/manifest.json")
      MIGRATION_URL="${REMOTE_BASE_URL}/migrations/${migration_key}.sh"
      curl -sf -o "$UPDATE_DIR/${migration_key}.sh" "$MIGRATION_URL"

      if [ ! -f "$UPDATE_DIR/${migration_key}.sh" ]; then
        echo "⚠️ Failed to download migration $migration_key, skipping"
        continue
      fi

      DOWNLOADED_HASH=$(sha256sum "$UPDATE_DIR/${migration_key}.sh" | awk '{print $1}')
      if [ "$EXPECTED_HASH" != "$DOWNLOADED_HASH" ]; then
        echo "❌ Hash mismatch for migration $migration_key, skipping"
        rm -f "$UPDATE_DIR/${migration_key}.sh"
        continue
      fi

      # Execute migration
      chmod +x "$UPDATE_DIR/${migration_key}.sh"
      echo "▶️ Running migration: $migration_key"
      if "$UPDATE_DIR/${migration_key}.sh" 2>&1; then
        # Record completion
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq --arg k "$migration_key" --arg t "$TIMESTAMP" '. + {($k): $t}' "$MIGRATIONS_STATE" > "$MIGRATIONS_STATE.tmp"
        mv "$MIGRATIONS_STATE.tmp" "$MIGRATIONS_STATE"
        echo "✅ Migration $migration_key completed"
      else
        echo "❌ Migration $migration_key failed (exit code: $?)"
      fi
      rm -f "$UPDATE_DIR/${migration_key}.sh"
    done
  fi

  # Call update.sh to handle docker compose restart if needed
  UPDATE_SH_PATH=$(jq -r '.files["update.sh"].path' "$UPDATE_DIR/manifest.json")
  if [ -f "$UPDATE_SH_PATH" ]; then
    "$UPDATE_SH_PATH"
  fi
else
  echo "✅ Already up to date"
fi
