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

# ============================================================================
# Process pre-existing trigger files on startup
# This handles files left over from service restarts or system reboots
# ============================================================================
process_trigger_file() {
    local file="$1"
    log_message "Processing pre-existing trigger file: $file"

    case "$file" in
        update_apps_immediate)
            log_message "=== APPS UPDATE (STARTUP RECOVERY) ==="
            log_message "Executing: /chuckey/scripts/check_and_fetch.sh"
            if /chuckey/scripts/check_and_fetch.sh >> "$LOG_FILE" 2>&1; then
                log_message "Apps update completed successfully"
            else
                log_message "Apps update failed with exit code $?"
            fi
            rm -f "$DATA_DIR"/update_apps_*
            log_message "Apps update trigger files cleaned up"
            ;;

        update_system_immediate)
            log_message "=== SYSTEM UPDATE (STARTUP RECOVERY) ==="
            log_message "Executing: apt update && apt upgrade"
            if apt update >> "$LOG_FILE" 2>&1 && apt upgrade -y >> "$LOG_FILE" 2>&1; then
                log_message "System update completed successfully"
            else
                log_message "System update failed with exit code $?"
            fi
            rm -f "$DATA_DIR"/update_system_*
            log_message "System update trigger files cleaned up"
            ;;

        network_change)
            log_message "=== NETWORK CHANGE (STARTUP RECOVERY) ==="
            if [[ -f "$DATA_DIR/network_change" ]]; then
                NETWORK_CONFIG=$(cat "$DATA_DIR/network_change")
                log_message "Network configuration: $NETWORK_CONFIG"
                if /chuckey/scripts/network_manager.sh set "$NETWORK_CONFIG" >> "$LOG_FILE" 2>&1; then
                    log_message "Network settings applied successfully"
                    touch "$DATA_DIR/network_change_success"
                else
                    ERROR_MSG=$(tail -1 "$LOG_FILE")
                    log_message "Network settings failed: $ERROR_MSG"
                    echo "$ERROR_MSG" > "$DATA_DIR/network_change_failed"
                fi
                rm -f "$DATA_DIR/network_change"
                log_message "Network change trigger file cleaned up"
            fi
            ;;

        setup_change_password)
            log_setup "=== PASSWORD CHANGE (STARTUP RECOVERY) ==="
            if [[ -f "$DATA_DIR/setup_change_password" ]]; then
                new_password=$(cat "$DATA_DIR/setup_change_password")
                if echo "chuckey:$new_password" | chpasswd 2>>"$SETUP_LOG_FILE"; then
                    log_setup "Password changed successfully for user 'chuckey'"
                    touch "$DATA_DIR/setup_password_changed"
                else
                    log_setup "ERROR: Failed to change password"
                    touch "$DATA_DIR/setup_password_failed"
                fi
                rm -f "$DATA_DIR/setup_change_password"
                log_setup "Removed trigger file: setup_change_password"
            fi
            ;;

        setup_change_locale)
            log_setup "=== LOCALE CHANGE (STARTUP RECOVERY) ==="
            if [[ -f "$DATA_DIR/setup_change_locale" ]]; then
                new_locale=$(cat "$DATA_DIR/setup_change_locale")
                log_setup "Changing locale to: $new_locale"
                locale_base="${new_locale%.*}"
                if ! locale -a 2>/dev/null | grep -qi "^${locale_base}"; then
                    log_setup "Generating locale: $new_locale"
                    locale-gen "$new_locale" >>"$SETUP_LOG_FILE" 2>&1
                fi
                if update-locale LANG="$new_locale" >>"$SETUP_LOG_FILE" 2>&1; then
                    log_setup "Locale changed successfully to: $new_locale"
                    touch "$DATA_DIR/setup_locale_changed"
                else
                    log_setup "ERROR: Failed to change locale"
                    touch "$DATA_DIR/setup_locale_failed"
                fi
                rm -f "$DATA_DIR/setup_change_locale"
                log_setup "Removed trigger file: setup_change_locale"
            fi
            ;;

        setup_change_timezone)
            log_setup "=== TIMEZONE CHANGE (STARTUP RECOVERY) ==="
            if [[ -f "$DATA_DIR/setup_change_timezone" ]]; then
                new_timezone=$(cat "$DATA_DIR/setup_change_timezone")
                log_setup "Changing timezone to: $new_timezone"
                if timedatectl set-timezone "$new_timezone" >>"$SETUP_LOG_FILE" 2>&1; then
                    log_setup "Timezone changed successfully to: $new_timezone"
                    touch "$DATA_DIR/setup_timezone_changed"
                else
                    log_setup "ERROR: Failed to change timezone"
                    touch "$DATA_DIR/setup_timezone_failed"
                fi
                rm -f "$DATA_DIR/setup_change_timezone"
                log_setup "Removed trigger file: setup_change_timezone"
            fi
            ;;

        app_install_*)
            # Skip completion/failure marker files
            if [[ "$file" == *_complete ]] || [[ "$file" == *_failed ]]; then
                return
            fi
            APP_ID="${file#app_install_}"
            log_message "=== APP INSTALL (STARTUP RECOVERY): $APP_ID ==="
            if [[ -f "$DATA_DIR/$file" ]]; then
                manage_apps
                rm -f "$DATA_DIR/$file"
                touch "$DATA_DIR/app_install_${APP_ID}_complete"
                log_message "App install trigger for $APP_ID cleaned up"
            fi
            ;;

        app_uninstall_*)
            # Skip completion/failure marker files
            if [[ "$file" == *_complete ]] || [[ "$file" == *_failed ]]; then
                return
            fi
            APP_ID="${file#app_uninstall_}"
            log_message "=== APP UNINSTALL (STARTUP RECOVERY): $APP_ID ==="
            if [[ -f "$DATA_DIR/$file" ]]; then
                manage_apps
                rm -f "$DATA_DIR/$file"
                touch "$DATA_DIR/app_uninstall_${APP_ID}_complete"
                log_message "App uninstall trigger for $APP_ID cleaned up"
            fi
            ;;
    esac
}

# ============================================================================
# App Management Function
# Runs docker compose with both main and apps compose files
# ============================================================================
manage_apps() {
    log_message "Managing app containers..."
    local COMPOSE_DIR="/chuckey"
    local MAIN_COMPOSE="$COMPOSE_DIR/docker-compose.yml"
    local APPS_COMPOSE="$COMPOSE_DIR/data/apps-compose.yml"

    # Build compose command
    local COMPOSE_CMD="docker compose -f $MAIN_COMPOSE"
    if [[ -f "$APPS_COMPOSE" ]]; then
        COMPOSE_CMD="$COMPOSE_CMD -f $APPS_COMPOSE"
        log_message "Including apps-compose.yml in deployment"

        # Create app data directories from volume mounts in apps-compose.yml
        # Extract host paths from volumes (format: /host/path:/container/path)
        if command -v grep &> /dev/null; then
            grep -oP '^\s*-\s*\K/chuckey/apps[^:]+' "$APPS_COMPOSE" 2>/dev/null | while read -r dir; do
                if [[ -n "$dir" && ! -d "$dir" ]]; then
                    log_message "Creating app directory: $dir"
                    mkdir -p "$dir"
                fi
            done
        fi
    fi

    # Pull any new images
    log_message "Pulling app images..."
    if $COMPOSE_CMD pull >> "$LOG_FILE" 2>&1; then
        log_message "App images pulled successfully"
    else
        log_message "WARNING: Some app images may have failed to pull"
    fi

    # Stop and remove containers first to avoid docker-compose 1.29.2 ContainerConfig bug
    # This bug occurs when recreating containers with newer Docker images
    log_message "Stopping containers for clean restart..."
    $COMPOSE_CMD down --remove-orphans >> "$LOG_FILE" 2>&1 || true

    log_message "Starting app containers..."
    if $COMPOSE_CMD up -d >> "$LOG_FILE" 2>&1; then
        log_message "App containers started successfully"
    else
        log_message "ERROR: Failed to start app containers"
        return 1
    fi

    return 0
}

# Check for pre-existing trigger files before starting inotifywait
log_message "Checking for pre-existing trigger files..."
KNOWN_TRIGGERS="update_apps_immediate update_system_immediate network_change setup_change_password setup_change_locale setup_change_timezone"
FOUND_TRIGGERS=0

for trigger in $KNOWN_TRIGGERS; do
    if [[ -f "$DATA_DIR/$trigger" ]]; then
        FOUND_TRIGGERS=$((FOUND_TRIGGERS + 1))
        process_trigger_file "$trigger"
    fi
done

# Also check for app install/uninstall triggers (pattern-based)
for trigger_file in "$DATA_DIR"/app_install_* "$DATA_DIR"/app_uninstall_*; do
    if [[ -f "$trigger_file" ]]; then
        trigger=$(basename "$trigger_file")
        FOUND_TRIGGERS=$((FOUND_TRIGGERS + 1))
        process_trigger_file "$trigger"
    fi
done

if [[ $FOUND_TRIGGERS -eq 0 ]]; then
    log_message "No pre-existing trigger files found"
else
    log_message "Processed $FOUND_TRIGGERS pre-existing trigger file(s)"
fi

log_message "Starting inotifywait monitor..."

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

        network_change)
            log_message "=== NETWORK SETTINGS CHANGE TRIGGERED ==="

            # Read network configuration from trigger file
            if [[ -f "$DATA_DIR/network_change" ]]; then
                NETWORK_CONFIG=$(cat "$DATA_DIR/network_change")
                log_message "Network configuration: $NETWORK_CONFIG"

                # Call network manager script with configuration
                if /chuckey/scripts/network_manager.sh set "$NETWORK_CONFIG" >> "$LOG_FILE" 2>&1; then
                    log_message "Network settings applied successfully"
                    touch "$DATA_DIR/network_change_success"
                else
                    ERROR_MSG=$(tail -1 "$LOG_FILE")
                    log_message "Network settings failed: $ERROR_MSG"
                    echo "$ERROR_MSG" > "$DATA_DIR/network_change_failed"
                fi

                # Clean up trigger file
                rm -f "$DATA_DIR/network_change"
                log_message "Network change trigger file cleaned up"
            fi
            ;;

        app_install_*)
            # Skip completion/failure marker files (they end with _complete or _failed)
            if [[ "$file" == *_complete ]] || [[ "$file" == *_failed ]]; then
                continue
            fi
            APP_ID="${file#app_install_}"
            log_message "=== APP INSTALL TRIGGERED: $APP_ID ==="

            if [[ -f "$DATA_DIR/$file" ]]; then
                if manage_apps; then
                    log_message "App $APP_ID installed successfully"
                    touch "$DATA_DIR/app_install_${APP_ID}_complete"
                else
                    log_message "ERROR: Failed to install app $APP_ID"
                    touch "$DATA_DIR/app_install_${APP_ID}_failed"
                fi

                # Clean up trigger file
                rm -f "$DATA_DIR/$file"
                log_message "App install trigger file cleaned up"
            fi
            ;;

        app_uninstall_*)
            # Skip completion/failure marker files (they end with _complete or _failed)
            if [[ "$file" == *_complete ]] || [[ "$file" == *_failed ]]; then
                continue
            fi
            APP_ID="${file#app_uninstall_}"
            log_message "=== APP UNINSTALL TRIGGERED: $APP_ID ==="

            if [[ -f "$DATA_DIR/$file" ]]; then
                if manage_apps; then
                    log_message "App $APP_ID uninstalled successfully"
                    touch "$DATA_DIR/app_uninstall_${APP_ID}_complete"
                else
                    log_message "ERROR: Failed to uninstall app $APP_ID"
                    touch "$DATA_DIR/app_uninstall_${APP_ID}_failed"
                fi

                # Clean up trigger file
                rm -f "$DATA_DIR/$file"
                log_message "App uninstall trigger file cleaned up"
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
