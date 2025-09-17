#!/bin/bash
# Chuckey Update Monitor - Instant execution via inotify
# This script monitors /chuckey/data/ for update trigger files and executes updates immediately

set -euo pipefail

LOG_FILE="/chuckey/logs/update.log"
DATA_DIR="/chuckey/data"

# Ensure required tools are installed
if ! command -v inotifywait &> /dev/null; then
    echo "ERROR: inotify-tools not installed. Install with: sudo apt-get install inotify-tools" >&2
    exit 1
fi

# Ensure directories exist
mkdir -p "$DATA_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "Chuckey Update Monitor started - watching $DATA_DIR"

# Monitor for file creation events
inotifywait -m -e create,moved_to "$DATA_DIR" --format '%f' | while read -r file; do
    case "$file" in
        update_apps_immediate)
            log_message "=== APPS UPDATE TRIGGERED ==="
            log_message "Executing: /chuckey/scripts/check_and_fetch.sh"

            # Execute apps update and capture output
            if /chuckey/scripts/check_and_fetch.sh >> "$LOG_FILE" 2>&1; then
                log_message "Apps update completed successfully"
            else
                log_message "Apps update failed with exit code $?"
            fi

            # Clean up trigger files
            rm -f "$DATA_DIR"/update_apps_*
            log_message "Apps update trigger files cleaned up"
            ;;

        update_system_immediate)
            log_message "=== SYSTEM UPDATE TRIGGERED ==="
            log_message "Executing: armbian-update"

            # Execute system update and capture output
            if armbian-update >> "$LOG_FILE" 2>&1; then
                log_message "System update completed successfully"
            else
                log_message "System update failed with exit code $?"
            fi

            # Clean up trigger files
            rm -f "$DATA_DIR"/update_system_*
            log_message "System update trigger files cleaned up"
            ;;

        *)
            # Ignore other files
            ;;
    esac
done