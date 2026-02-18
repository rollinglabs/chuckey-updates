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

# Mask sensitive values in commands for safe logging
# Replaces quoted strings after "setpassword" with ***
mask_sensitive_command() {
    local cmd="$1"
    # Mask pihole setpassword 'password' or "password"
    echo "$cmd" | sed -E "s/(setpassword\s+)['\"][^'\"]*['\"]/\1'***'/g"
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
            # Step 1: Check for official Chuckey updates (pinned container images)
            log_message "Checking for Chuckey updates..."
            log_message "Executing: /chuckey/scripts/check_and_fetch.sh"
            if /chuckey/scripts/check_and_fetch.sh >> "$LOG_FILE" 2>&1; then
                log_message "Chuckey update check completed successfully"
            else
                log_message "Chuckey update check failed with exit code $?"
            fi
            # Step 2: Update installed marketplace apps (pull latest images)
            update_installed_apps
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
                # Read trigger file to check for hooks and commands
                TRIGGER_CONTENT=$(cat "$DATA_DIR/$file" 2>/dev/null)
                PRE_INSTALL=$(echo "$TRIGGER_CONTENT" | grep -oP '"pre_install"\s*:\s*"\K[^"]+' 2>/dev/null || true)
                POST_INSTALL_CMD=$(echo "$TRIGGER_CONTENT" | grep -oP '"post_install_command"\s*:\s*"\K[^"]+' 2>/dev/null || true)

                # Run pre_install hook if specified
                if [[ -n "$PRE_INSTALL" ]]; then
                    log_message "Running pre_install hook: $PRE_INSTALL"
                    run_app_hook "$PRE_INSTALL"
                fi

                if manage_app "install" "$APP_ID"; then
                    # Run post_install_command if specified
                    if [[ -n "$POST_INSTALL_CMD" ]]; then
                        log_message "Running post_install_command for $APP_ID..."
                        CONTAINER_NAME="$APP_ID"
                        WAIT_COUNT=0
                        while [[ $WAIT_COUNT -lt 30 ]]; do
                            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                                break
                            fi
                            sleep 1
                            WAIT_COUNT=$((WAIT_COUNT + 1))
                        done
                        if [[ $WAIT_COUNT -lt 30 ]]; then
                            sleep 5
                            log_message "Executing: $(mask_sensitive_command "$POST_INSTALL_CMD")"
                            eval "$POST_INSTALL_CMD" >> "$LOG_FILE" 2>&1 || true
                        fi
                    fi
                    touch "$DATA_DIR/app_install_${APP_ID}_complete"
                fi
                rm -f "$DATA_DIR/$file"
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
                # Read trigger file to check for post_uninstall hook
                TRIGGER_CONTENT=$(cat "$DATA_DIR/$file" 2>/dev/null)
                POST_UNINSTALL=$(echo "$TRIGGER_CONTENT" | grep -oP '"post_uninstall"\s*:\s*"\K[^"]+' 2>/dev/null || true)

                if manage_app "uninstall" "$APP_ID"; then
                    touch "$DATA_DIR/app_uninstall_${APP_ID}_complete"
                    # Run post_uninstall hook if specified
                    if [[ -n "$POST_UNINSTALL" ]]; then
                        log_message "Running post_uninstall hook: $POST_UNINSTALL"
                        run_app_hook "$POST_UNINSTALL"
                    fi
                fi
                rm -f "$DATA_DIR/$file"
                log_message "App uninstall trigger for $APP_ID cleaned up"
            fi
            ;;
    esac
}

# ============================================================================
# App Hook Functions
# Handle pre-install and post-uninstall hooks for apps
# ============================================================================
run_app_hook() {
    local hook_name="$1"
    log_message "Running app hook: $hook_name"

    case "$hook_name" in
        disable_resolved_stub)
            # Disable systemd-resolved stub listener to free port 53 for Pi-hole
            log_message "Disabling systemd-resolved DNS stub listener..."
            if [[ -f /etc/systemd/resolved.conf ]]; then
                # Backup original config
                cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak 2>/dev/null || true
                # Disable the stub listener
                if grep -q "^DNSStubListener=" /etc/systemd/resolved.conf; then
                    sed -i 's/^DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                elif grep -q "^#DNSStubListener=" /etc/systemd/resolved.conf; then
                    sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                else
                    echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
                fi
                # Restart systemd-resolved
                systemctl restart systemd-resolved >> "$LOG_FILE" 2>&1
                log_message "systemd-resolved stub listener disabled"
            else
                log_message "WARNING: /etc/systemd/resolved.conf not found"
            fi
            ;;

        enable_resolved_stub)
            # Re-enable systemd-resolved stub listener
            log_message "Re-enabling systemd-resolved DNS stub listener..."
            if [[ -f /etc/systemd/resolved.conf.bak ]]; then
                # Restore backup
                cp /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf
                systemctl restart systemd-resolved >> "$LOG_FILE" 2>&1
                log_message "systemd-resolved stub listener re-enabled"
            elif [[ -f /etc/systemd/resolved.conf ]]; then
                # Just enable the stub listener
                if grep -q "^DNSStubListener=" /etc/systemd/resolved.conf; then
                    sed -i 's/^DNSStubListener=.*/DNSStubListener=yes/' /etc/systemd/resolved.conf
                fi
                systemctl restart systemd-resolved >> "$LOG_FILE" 2>&1
                log_message "systemd-resolved stub listener re-enabled"
            fi
            ;;

        *)
            log_message "WARNING: Unknown hook: $hook_name"
            ;;
    esac
}

# ============================================================================
# App Management Function
# Manages individual app containers without affecting core services
# Usage: manage_app <action> <app_id>
#   action: "install" or "uninstall"
#   app_id: the app container name (e.g., "pihole")
# ============================================================================
manage_app() {
    local ACTION="$1"
    local APP_ID="$2"
    local COMPOSE_DIR="/chuckey"
    local MAIN_COMPOSE="$COMPOSE_DIR/docker-compose.yml"
    local APPS_COMPOSE="$COMPOSE_DIR/data/apps-compose.yml"

    log_message "Managing app container: $APP_ID (action: $ACTION)"

    case "$ACTION" in
        install)
            # For install, we need apps-compose.yml
            if [[ ! -f "$APPS_COMPOSE" ]]; then
                log_message "ERROR: apps-compose.yml not found - cannot install"
                return 1
            fi

            # Build compose command
            local COMPOSE_CMD="docker compose -f $MAIN_COMPOSE -f $APPS_COMPOSE"
            log_message "Including apps-compose.yml"

            # Create app data directories from volume mounts in apps-compose.yml
            if command -v grep &> /dev/null; then
                grep -oP '^\s*-\s*\K/chuckey/apps[^:]+' "$APPS_COMPOSE" 2>/dev/null | while read -r dir; do
                    if [[ -n "$dir" && ! -d "$dir" ]]; then
                        log_message "Creating app directory: $dir"
                        mkdir -p "$dir"
                    fi
                done
            fi

            # Pull image for this specific app
            log_message "Pulling image for $APP_ID..."
            if $COMPOSE_CMD pull "$APP_ID" >> "$LOG_FILE" 2>&1; then
                log_message "Image pulled successfully for $APP_ID"
            else
                log_message "WARNING: Failed to pull image for $APP_ID (may use cached)"
            fi

            # Start only this app container (doesn't affect other containers)
            log_message "Starting container: $APP_ID..."
            if $COMPOSE_CMD up -d "$APP_ID" >> "$LOG_FILE" 2>&1; then
                log_message "Container $APP_ID started successfully"
            else
                log_message "ERROR: Failed to start container $APP_ID"
                return 1
            fi
            ;;

        uninstall)
            # For uninstall, we can use docker directly - don't need compose file
            log_message "Stopping and removing container: $APP_ID..."

            # Stop the container
            if docker stop "$APP_ID" >> "$LOG_FILE" 2>&1; then
                log_message "Container $APP_ID stopped"
            else
                log_message "WARNING: Failed to stop container $APP_ID (may not be running)"
            fi

            # Remove the container
            if docker rm "$APP_ID" >> "$LOG_FILE" 2>&1; then
                log_message "Container $APP_ID removed successfully"
            else
                log_message "WARNING: Failed to remove container $APP_ID (may not exist)"
            fi
            ;;

        *)
            log_message "ERROR: Unknown action: $ACTION"
            return 1
            ;;
    esac

    return 0
}

# ============================================================================
# Update Installed Apps Function
# Pulls latest images for installed apps (from apps-compose.yml) and recreates
# containers if images have changed. Also runs app-specific update commands
# (e.g., pihole -g for gravity updates). Does NOT affect core services.
# ============================================================================
update_installed_apps() {
    local COMPOSE_DIR="/chuckey"
    local MAIN_COMPOSE="$COMPOSE_DIR/docker-compose.yml"
    local APPS_COMPOSE="$COMPOSE_DIR/data/apps-compose.yml"
    local APPS_STATE="$COMPOSE_DIR/data/apps.json"

    # Check if there are any installed apps
    if [[ ! -f "$APPS_COMPOSE" ]]; then
        log_message "No installed apps to update (apps-compose.yml not found)"
        return 0
    fi

    log_message "Checking for app updates..."

    # Build compose command with both files (needed for networking/dependencies)
    local COMPOSE_CMD="docker compose -f $MAIN_COMPOSE -f $APPS_COMPOSE"

    # Get list of app service names from apps-compose.yml (exclude core services)
    local APP_SERVICES
    APP_SERVICES=$(docker compose -f "$APPS_COMPOSE" config --services 2>/dev/null || true)

    if [[ -z "$APP_SERVICES" ]]; then
        log_message "No app services found in apps-compose.yml"
        return 0
    fi

    # Pull latest images for app services only (not core services like chuckey-ui)
    log_message "Pulling latest images for installed apps..."
    if $COMPOSE_CMD pull $APP_SERVICES >> "$LOG_FILE" 2>&1; then
        log_message "App images pulled successfully"
    else
        log_message "WARNING: Some app images may have failed to pull"
    fi

    # Recreate app containers if images changed (without affecting core services)
    log_message "Updating app containers..."
    for service in $APP_SERVICES; do
        log_message "Checking container: $service"
        # Stop and remove existing container first to avoid docker-compose v1.29.2
        # ContainerConfig KeyError when new image lacks ContainerConfig field
        log_message "Stopping $service for clean recreate..."
        docker stop "$service" >> "$LOG_FILE" 2>&1 || true
        docker rm "$service" >> "$LOG_FILE" 2>&1 || true
        if $COMPOSE_CMD up -d "$service" >> "$LOG_FILE" 2>&1; then
            log_message "Container $service updated"
        else
            log_message "WARNING: Failed to update container $service"
        fi
    done

    # Run app-specific update commands (e.g., pihole -g for gravity updates)
    if [[ -f "$APPS_STATE" ]]; then
        log_message "Running app-specific update commands..."
        # Parse apps.json to find update_command for each installed app
        for app_id in $APP_SERVICES; do
            # Extract update_command for this app from apps.json using grep/sed (no jq dependency)
            local UPDATE_CMD
            UPDATE_CMD=$(grep -A5 "\"$app_id\"" "$APPS_STATE" 2>/dev/null | grep '"update_command"' | sed 's/.*"update_command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

            if [[ -n "$UPDATE_CMD" ]]; then
                log_message "Running update command for $app_id: $UPDATE_CMD"
                if eval "$UPDATE_CMD" >> "$LOG_FILE" 2>&1; then
                    log_message "Update command for $app_id completed successfully"
                else
                    log_message "WARNING: Update command for $app_id failed (exit code $?)"
                fi
            fi
        done
    fi

    log_message "App updates completed"
    return 0
}

# Legacy function for backwards compatibility with startup recovery
# This is called when we don't have a specific app_id context
manage_apps() {
    log_message "Managing all app containers..."
    local COMPOSE_DIR="/chuckey"
    local MAIN_COMPOSE="$COMPOSE_DIR/docker-compose.yml"
    local APPS_COMPOSE="$COMPOSE_DIR/data/apps-compose.yml"

    # Build compose command
    local COMPOSE_CMD="docker compose -f $MAIN_COMPOSE"
    if [[ -f "$APPS_COMPOSE" ]]; then
        COMPOSE_CMD="$COMPOSE_CMD -f $APPS_COMPOSE"
        log_message "Including apps-compose.yml in deployment"

        # Create app data directories from volume mounts in apps-compose.yml
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

    # Only start/restart app containers - don't touch core services
    # Use --no-recreate to avoid restarting existing healthy containers
    log_message "Starting app containers..."
    if $COMPOSE_CMD up -d --remove-orphans >> "$LOG_FILE" 2>&1; then
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

            # Step 1: Check for official Chuckey updates (pinned container images)
            log_message "Checking for Chuckey updates..."
            log_message "Executing: /chuckey/scripts/check_and_fetch.sh"
            if /chuckey/scripts/check_and_fetch.sh >> "$LOG_FILE" 2>&1; then
                log_message "Chuckey update check completed successfully"
            else
                log_message "Chuckey update check failed with exit code $?"
            fi

            # Step 2: Update installed marketplace apps (pull latest images)
            update_installed_apps

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
                # Read trigger file to check for hooks and commands
                TRIGGER_CONTENT=$(cat "$DATA_DIR/$file" 2>/dev/null)
                PRE_INSTALL=$(echo "$TRIGGER_CONTENT" | grep -oP '"pre_install"\s*:\s*"\K[^"]+' 2>/dev/null || true)
                POST_INSTALL_CMD=$(echo "$TRIGGER_CONTENT" | grep -oP '"post_install_command"\s*:\s*"\K[^"]+' 2>/dev/null || true)

                # Run pre_install hook if specified
                if [[ -n "$PRE_INSTALL" ]]; then
                    log_message "Running pre_install hook: $PRE_INSTALL"
                    run_app_hook "$PRE_INSTALL"
                fi

                if manage_app "install" "$APP_ID"; then
                    log_message "App $APP_ID installed successfully"

                    # Run post_install_command if specified
                    if [[ -n "$POST_INSTALL_CMD" ]]; then
                        log_message "Running post_install_command for $APP_ID..."
                        # Wait for container to be running (up to 30 seconds)
                        CONTAINER_NAME="$APP_ID"
                        WAIT_COUNT=0
                        while [[ $WAIT_COUNT -lt 30 ]]; do
                            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                                log_message "Container $CONTAINER_NAME is running"
                                break
                            fi
                            sleep 1
                            WAIT_COUNT=$((WAIT_COUNT + 1))
                        done

                        if [[ $WAIT_COUNT -lt 30 ]]; then
                            # Give container a few more seconds to fully initialize
                            sleep 5
                            log_message "Executing: $(mask_sensitive_command "$POST_INSTALL_CMD")"
                            if eval "$POST_INSTALL_CMD" >> "$LOG_FILE" 2>&1; then
                                log_message "Post-install command completed successfully"
                            else
                                log_message "WARNING: Post-install command failed (exit code $?)"
                            fi
                        else
                            log_message "WARNING: Container $CONTAINER_NAME not running after 30s, skipping post_install_command"
                        fi
                    fi

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
                # Read trigger file to check for post_uninstall hook
                TRIGGER_CONTENT=$(cat "$DATA_DIR/$file" 2>/dev/null)
                POST_UNINSTALL=$(echo "$TRIGGER_CONTENT" | grep -oP '"post_uninstall"\s*:\s*"\K[^"]+' 2>/dev/null || true)

                if manage_app "uninstall" "$APP_ID"; then
                    log_message "App $APP_ID uninstalled successfully"
                    touch "$DATA_DIR/app_uninstall_${APP_ID}_complete"

                    # Run post_uninstall hook if specified (only on success)
                    if [[ -n "$POST_UNINSTALL" ]]; then
                        log_message "Running post_uninstall hook: $POST_UNINSTALL"
                        run_app_hook "$POST_UNINSTALL"
                    fi
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
