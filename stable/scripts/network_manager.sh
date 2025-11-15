#!/bin/bash
#
# Network Manager Script
# Manages network configuration via NetworkManager (nmcli)
#
# Usage:
#   network_manager.sh get              - Return current network settings as JSON
#   network_manager.sh set <json>       - Apply network settings from JSON string
#

set -euo pipefail

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Validate IP address format
validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Check each octet is 0-255
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

# Validate netmask
validate_netmask() {
    local mask="$1"
    # Common netmasks
    case "$mask" in
        255.255.255.0|255.255.0.0|255.0.0.0|255.255.255.128|255.255.255.192|255.255.255.224|255.255.255.240|255.255.255.248|255.255.255.252)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Convert netmask to CIDR prefix
netmask_to_cidr() {
    local mask="$1"
    case "$mask" in
        255.255.255.252) echo "30" ;;
        255.255.255.248) echo "29" ;;
        255.255.255.240) echo "28" ;;
        255.255.255.224) echo "27" ;;
        255.255.255.192) echo "26" ;;
        255.255.255.128) echo "25" ;;
        255.255.255.0)   echo "24" ;;
        255.255.0.0)     echo "16" ;;
        255.0.0.0)       echo "8" ;;
        *) echo "24" ;;  # Default to /24
    esac
}

# Get primary ethernet connection name
get_primary_connection() {
    # Find active ethernet connection (not docker or loopback)
    nmcli -t -f NAME,TYPE,DEVICE con show --active | \
        grep -E "ethernet|802-3-ethernet" | \
        grep -v "docker" | \
        head -1 | \
        cut -d: -f1
}

# Get primary ethernet device
get_primary_device() {
    nmcli -t -f DEVICE,TYPE device status | \
        grep "ethernet" | \
        grep -v "docker" | \
        head -1 | \
        cut -d: -f1
}

# GET mode: Return current network configuration
get_network_config() {
    local connection
    connection=$(get_primary_connection)

    if [[ -z "$connection" ]]; then
        echo '{"error": "No active ethernet connection found"}'
        return 1
    fi

    local device
    device=$(get_primary_device)

    # Get connection method
    local method
    method=$(nmcli -t -f ipv4.method con show "$connection" | cut -d: -f2)

    # Map nmcli method to our mode
    local mode="dhcp"
    if [[ "$method" == "manual" ]]; then
        mode="manual"
    fi

    # Get current IP address from device (actual runtime config)
    local current_ip=""
    local current_netmask=""
    local current_cidr="24"

    if [[ -n "$device" ]]; then
        # Extract IP/CIDR from ip addr show
        local ip_info
        ip_info=$(ip -4 addr show "$device" | grep "inet " | head -1 | awk '{print $2}')

        if [[ -n "$ip_info" ]]; then
            current_ip=$(echo "$ip_info" | cut -d/ -f1)
            current_cidr=$(echo "$ip_info" | cut -d/ -f2)

            # Convert CIDR to netmask for display
            case "$current_cidr" in
                8)  current_netmask="255.0.0.0" ;;
                16) current_netmask="255.255.0.0" ;;
                24) current_netmask="255.255.255.0" ;;
                25) current_netmask="255.255.255.128" ;;
                26) current_netmask="255.255.255.192" ;;
                27) current_netmask="255.255.255.224" ;;
                28) current_netmask="255.255.255.240" ;;
                29) current_netmask="255.255.255.248" ;;
                30) current_netmask="255.255.255.252" ;;
                *)  current_netmask="255.255.255.0" ;;
            esac
        fi
    fi

    # Get gateway
    local gateway=""
    if [[ -n "$device" ]]; then
        gateway=$(ip route show dev "$device" | grep "default" | awk '{print $3}' | head -1)
    fi

    # Get DNS servers
    local dns_servers=""
    if [[ -f /etc/resolv.conf ]]; then
        dns_servers=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    fi

    # Get connection status
    local status="connected"
    local device_state
    device_state=$(nmcli -t -f STATE device show "$device" 2>/dev/null | cut -d: -f2 || echo "unknown")
    if [[ "$device_state" != "100" ]] && [[ "$device_state" != "connected" ]]; then
        status="disconnected"
    fi

    # Build JSON response
    cat <<EOF
{
  "interface": "$device",
  "connection": "$connection",
  "mode": "$mode",
  "ip": "$current_ip",
  "netmask": "$current_netmask",
  "gateway": "$gateway",
  "dns": "$dns_servers",
  "status": "$status"
}
EOF
}

# SET mode: Apply network configuration
set_network_config() {
    local json="$1"

    # Parse JSON using jq
    if ! command -v jq &> /dev/null; then
        echo '{"error": "jq not installed"}'
        return 1
    fi

    local mode
    mode=$(echo "$json" | jq -r '.mode // "dhcp"')

    log "Applying network configuration: mode=$mode"

    # Get primary connection
    local connection
    connection=$(get_primary_connection)

    if [[ -z "$connection" ]]; then
        echo '{"error": "No active ethernet connection found"}'
        return 1
    fi

    log "Using connection: $connection"

    # Apply based on mode
    if [[ "$mode" == "dhcp" ]]; then
        log "Switching to DHCP mode"

        # Set method to auto (DHCP) and remove static addresses
        nmcli con mod "$connection" ipv4.method auto
        nmcli con mod "$connection" -ipv4.addresses 2>/dev/null || true
        nmcli con mod "$connection" -ipv4.gateway 2>/dev/null || true

        # Restart connection to apply DHCP
        # Down first to release any static IP, then up to get DHCP lease
        nmcli con down "$connection" 2>&1 | head -5
        sleep 1
        nmcli con up "$connection" 2>&1 | head -5

        log "DHCP configuration applied successfully"
        echo '{"status": "success", "message": "DHCP enabled"}'

    elif [[ "$mode" == "manual" ]]; then
        # Extract manual settings
        local ip
        local netmask
        local gateway

        ip=$(echo "$json" | jq -r '.ip // ""')
        netmask=$(echo "$json" | jq -r '.netmask // ""')
        gateway=$(echo "$json" | jq -r '.gateway // ""')

        # Validate required fields
        if [[ -z "$ip" ]] || [[ -z "$netmask" ]] || [[ -z "$gateway" ]]; then
            echo '{"error": "Missing required fields for manual mode: ip, netmask, gateway"}'
            return 1
        fi

        # Validate IP format
        if ! validate_ip "$ip"; then
            echo '{"error": "Invalid IP address format"}'
            return 1
        fi

        if ! validate_ip "$gateway"; then
            echo '{"error": "Invalid gateway address format"}'
            return 1
        fi

        # Validate netmask
        if ! validate_netmask "$netmask"; then
            echo '{"error": "Invalid netmask (use 255.255.255.0, 255.255.0.0, etc.)"}'
            return 1
        fi

        # Convert netmask to CIDR
        local cidr
        cidr=$(netmask_to_cidr "$netmask")

        log "Switching to manual mode: IP=$ip/$cidr Gateway=$gateway"

        # Apply manual configuration (set addresses BEFORE method)
        nmcli con mod "$connection" ipv4.addresses "$ip/$cidr"
        nmcli con mod "$connection" ipv4.gateway "$gateway"
        nmcli con mod "$connection" ipv4.method manual

        # Set DNS if provided, otherwise use Google DNS
        local dns
        dns=$(echo "$json" | jq -r '.dns // "8.8.8.8,8.8.4.4"')
        nmcli con mod "$connection" ipv4.dns "$dns"

        # Restart connection
        nmcli con up "$connection" 2>&1 | head -5

        log "Manual configuration applied successfully"
        echo '{"status": "success", "message": "Static IP configured"}'

    else
        echo '{"error": "Invalid mode (must be dhcp or manual)"}'
        return 1
    fi
}

# Main execution
case "${1:-}" in
    get)
        get_network_config
        ;;
    set)
        if [[ -z "${2:-}" ]]; then
            echo '{"error": "Missing JSON configuration for set mode"}'
            exit 1
        fi
        set_network_config "$2"
        ;;
    *)
        echo "Usage: $0 {get|set <json>}"
        echo ""
        echo "Examples:"
        echo "  $0 get"
        echo "  $0 set '{\"mode\":\"dhcp\"}'"
        echo "  $0 set '{\"mode\":\"manual\",\"ip\":\"192.168.1.100\",\"netmask\":\"255.255.255.0\",\"gateway\":\"192.168.1.1\"}'"
        exit 1
        ;;
esac
