#!/bin/bash
# Chuckey Trigger Monitor - Handles all trigger files (updates, setup, configuration)

set -euo pipefail

LOG_FILE="/chuckey/logs/update.log"
SETUP_LOG_FILE="/chuckey/logs/setup.log"
DATA_DIR="/chuckey/data"

# Ensure required tools are installed
if ! command -v inotifywait &> /dev/null; then
    echo "ERROR: inotify-tools not installed. Install with: sudo apt-get install inotify-tools" >&2
    exit 1
fi

# Ensure directories exist
mkdir -p "$DATA_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$SETUP_LOG_FILE")"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_setup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SETUP_LOG_FILE"
}

log_message "Chuckey Trigger Monitor started - watching $DATA_DIR"

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
            log_message "Executing: apt update && apt upgrade"

            # Execute system update and capture output
            if apt update >> "$LOG_FILE" 2>&1 && apt upgrade -y >> "$LOG_FILE" 2>&1; then
                log_message "System update completed successfully"
            else
                log_message "System update failed with exit code $?"
            fi

            # Clean up trigger files
            rm -f "$DATA_DIR"/update_system_*
            log_message "System update trigger files cleaned up"
            ;;

        setup_change_password)
            log_setup "=== PASSWORD CHANGE TRIGGERED ==="

            # Read password from trigger file
            if [[ -f "$DATA_DIR/setup_change_password" ]]; then
                new_password=$(cat "$DATA_DIR/setup_change_password")

                # Change chuckey user password
                if echo "chuckey:$new_password" | chpasswd 2>>"$SETUP_LOG_FILE"; then
                    log_setup "Password changed successfully for user 'chuckey'"
                    touch "$DATA_DIR/setup_password_changed"
                    log_setup "Created success marker: setup_password_changed"
                else
                    log_setup "ERROR: Failed to change password"
                    touch "$DATA_DIR/setup_password_failed"
                fi

                # Remove trigger file
                rm -f "$DATA_DIR/setup_change_password"
                log_setup "Removed trigger file: setup_change_password"
            else
                log_setup "WARNING: Trigger file disappeared before processing"
            fi
            ;;

        setup_change_locale)
            log_setup "=== LOCALE CHANGE TRIGGERED ==="

            # Read locale from trigger file
            if [[ -f "$DATA_DIR/setup_change_locale" ]]; then
                new_locale=$(cat "$DATA_DIR/setup_change_locale")
                log_setup "Changing locale to: $new_locale"

                # Check if locale is already available (normalize case for UTF-8 vs utf8)
                # locale -a outputs lowercase .utf8, but locales can be specified as .UTF-8
                locale_base="${new_locale%.*}"  # e.g., en_GB from en_GB.UTF-8
                if locale -a 2>/dev/null | grep -qi "^${locale_base}"; then
                    log_setup "Locale already available: $new_locale"
                else
                    log_setup "Generating locale: $new_locale"
                    locale-gen "$new_locale" >>"$SETUP_LOG_FILE" 2>&1
                fi

                # Set as system default
                if update-locale LANG="$new_locale" >>"$SETUP_LOG_FILE" 2>&1; then
                    log_setup "Locale changed successfully to: $new_locale"
                    touch "$DATA_DIR/setup_locale_changed"
                    log_setup "Created success marker: setup_locale_changed"
                else
                    log_setup "ERROR: Failed to change locale"
                    touch "$DATA_DIR/setup_locale_failed"
                fi

                # Remove trigger file
                rm -f "$DATA_DIR/setup_change_locale"
                log_setup "Removed trigger file: setup_change_locale"
            else
                log_setup "WARNING: Trigger file disappeared before processing"
            fi
            ;;

        setup_change_timezone)
            log_setup "=== TIMEZONE CHANGE TRIGGERED ==="

            # Read timezone from trigger file
            if [[ -f "$DATA_DIR/setup_change_timezone" ]]; then
                new_timezone=$(cat "$DATA_DIR/setup_change_timezone")
                log_setup "Changing timezone to: $new_timezone"

                # Set timezone using timedatectl
                if timedatectl set-timezone "$new_timezone" >>"$SETUP_LOG_FILE" 2>&1; then
                    log_setup "Timezone changed successfully to: $new_timezone"
                    touch "$DATA_DIR/setup_timezone_changed"
                    log_setup "Created success marker: setup_timezone_changed"
                else
                    log_setup "ERROR: Failed to change timezone"
                    touch "$DATA_DIR/setup_timezone_failed"
                fi

                # Remove trigger file
                rm -f "$DATA_DIR/setup_change_timezone"
                log_setup "Removed trigger file: setup_change_timezone"
            else
                log_setup "WARNING: Trigger file disappeared before processing"
            fi
            ;;

        setup_*)
            # Log other setup events for debugging
            log_setup "Setup event detected: $file"
            ;;

        *)
            # Ignore other files
            ;;
    esac
done
