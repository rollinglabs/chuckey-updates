# Network Settings API - Flask Integration Guide

## Overview

This document describes the Flask integration pattern for network settings management in the Chuckey UI. The backend uses a trigger file pattern where Flask writes JSON configuration to `/chuckey/data/network_change`, which is then processed by `update_monitor.sh` running as root via systemd.

## Architecture

```
Flask UI (chuckey-ui container)
    │
    ├─> GET /api/network → Read current network config
    │   └─> Calls: network_manager.sh get
    │
    └─> POST /api/network → Apply new network config
        └─> Writes: /chuckey/data/network_change (trigger file)
            └─> inotify detects file creation
                └─> update_monitor.sh processes trigger
                    └─> Calls: network_manager.sh set <json>
                        └─> Creates: network_change_success OR network_change_failed
```

## GET Endpoint: Fetch Current Network Settings

### Flask Route Example
```python
@app.route('/api/network', methods=['GET'])
def get_network_settings():
    """Get current network configuration"""
    try:
        result = subprocess.run(
            ['/chuckey/scripts/network_manager.sh', 'get'],
            capture_output=True,
            text=True,
            check=True
        )
        return jsonify(json.loads(result.stdout))
    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

### Response Format
```json
{
  "interface": "eth0",
  "connection": "Wired connection 1",
  "mode": "dhcp",
  "ip": "172.16.1.54",
  "netmask": "255.255.255.0",
  "gateway": "172.16.1.254",
  "dns": "8.8.8.8,8.8.4.4",
  "status": "connected"
}
```

#### Response Fields
- `interface` (string): Network interface name (e.g., "eth0")
- `connection` (string): NetworkManager connection name
- `mode` (string): Either "dhcp" or "manual"
- `ip` (string): Current IP address
- `netmask` (string): Subnet mask in dotted decimal notation
- `gateway` (string): Default gateway IP
- `dns` (string): Comma-separated DNS servers
- `status` (string): Connection status ("connected" or "disconnected")

## POST Endpoint: Apply Network Settings

### Flask Route Example
```python
import json
import os
import time

@app.route('/api/network', methods=['POST'])
def set_network_settings():
    """Apply network configuration via trigger file"""
    try:
        config = request.get_json()

        # Validate required fields
        if 'mode' not in config:
            return jsonify({'error': 'Missing required field: mode'}), 400

        if config['mode'] == 'manual':
            required = ['ip', 'netmask', 'gateway']
            missing = [f for f in required if f not in config]
            if missing:
                return jsonify({'error': f'Missing required fields: {", ".join(missing)}'}), 400

        # Clean up any previous status markers
        for marker in ['network_change_success', 'network_change_failed']:
            marker_path = f'/chuckey/data/{marker}'
            if os.path.exists(marker_path):
                os.remove(marker_path)

        # Write trigger file
        trigger_path = '/chuckey/data/network_change'
        with open(trigger_path, 'w') as f:
            json.dump(config, f)

        # Wait for processing (max 15 seconds)
        max_wait = 15
        start_time = time.time()

        while time.time() - start_time < max_wait:
            # Check for success marker
            if os.path.exists('/chuckey/data/network_change_success'):
                os.remove('/chuckey/data/network_change_success')
                return jsonify({'status': 'success', 'message': 'Network settings applied'})

            # Check for failure marker
            if os.path.exists('/chuckey/data/network_change_failed'):
                with open('/chuckey/data/network_change_failed', 'r') as f:
                    error_msg = f.read().strip()
                os.remove('/chuckey/data/network_change_failed')
                return jsonify({'status': 'error', 'message': error_msg}), 500

            time.sleep(0.5)

        # Timeout - no response from update_monitor
        return jsonify({'status': 'error', 'message': 'Timeout waiting for network change'}), 500

    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

### Request Format - DHCP Mode
```json
{
  "mode": "dhcp"
}
```

### Request Format - Manual Mode
```json
{
  "mode": "manual",
  "ip": "192.168.1.100",
  "netmask": "255.255.255.0",
  "gateway": "192.168.1.1",
  "dns": "8.8.8.8,8.8.4.4"
}
```

#### Request Fields
- `mode` (string, required): Either "dhcp" or "manual"
- `ip` (string, required for manual): Static IP address
- `netmask` (string, required for manual): Subnet mask (255.255.255.0, 255.255.0.0, etc.)
- `gateway` (string, required for manual): Default gateway IP
- `dns` (string, optional): Comma-separated DNS servers (defaults to "8.8.8.8,8.8.4.4")

### Response Format - Success
```json
{
  "status": "success",
  "message": "Network settings applied"
}
```

### Response Format - Error
```json
{
  "status": "error",
  "message": "Invalid IP address format"
}
```

## Validation Rules

### IP Address Validation
- Format: `XXX.XXX.XXX.XXX` where XXX is 0-255
- Example: `192.168.1.100`

### Netmask Validation
Accepted netmasks:
- `255.255.255.252` (/30)
- `255.255.255.248` (/29)
- `255.255.255.240` (/28)
- `255.255.255.224` (/27)
- `255.255.255.192` (/26)
- `255.255.255.128` (/25)
- `255.255.255.0` (/24)
- `255.255.0.0` (/16)
- `255.0.0.0` (/8)

### Mode Validation
- Must be either "dhcp" or "manual"

## Error Messages

| Error | Description |
|-------|-------------|
| `Missing required field: mode` | POST request missing mode field |
| `Missing required fields: ip, netmask, gateway` | Manual mode missing required fields |
| `Invalid mode (must be dhcp or manual)` | Mode field contains invalid value |
| `Invalid IP address format` | IP address doesn't match XXX.XXX.XXX.XXX pattern |
| `Invalid netmask` | Netmask not in list of accepted values |
| `No active ethernet connection found` | NetworkManager can't find ethernet connection |
| `Timeout waiting for network change` | update_monitor.sh didn't process trigger within 15 seconds |

## Important Notes

### Connection Loss Warning
When switching network modes, the client may temporarily lose connection to the device:

- **DHCP → Manual**: Connection will be maintained if the new static IP is different from current DHCP IP
- **Manual → DHCP**: Connection may be lost temporarily as the device obtains a new DHCP lease

**UI Recommendation**: Display a warning message to the user:
> "Changing network settings may temporarily disconnect your session. The device will be accessible at the new IP address after the change is applied."

### Status Marker Files
The backend creates marker files in `/chuckey/data/`:

- `network_change_success`: Created on successful network change
- `network_change_failed`: Created on error (contains error message)

These files should be cleaned up before creating a new trigger to avoid stale status.

### DNS Defaults
If DNS is not provided in manual mode, the system defaults to Google DNS:
- Primary: `8.8.8.8`
- Secondary: `8.8.4.4`

### Processing Time
Typical processing times:
- **Manual mode**: 2-5 seconds
- **DHCP mode**: 2-8 seconds (depends on DHCP server response)

The Flask endpoint should wait up to 15 seconds for completion.

## Testing

### Test DHCP Mode
```bash
curl -X POST http://localhost:5000/api/network \
  -H "Content-Type: application/json" \
  -d '{"mode":"dhcp"}'
```

### Test Manual Mode
```bash
curl -X POST http://localhost:5000/api/network \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "manual",
    "ip": "192.168.1.100",
    "netmask": "255.255.255.0",
    "gateway": "192.168.1.1"
  }'
```

### Test GET
```bash
curl http://localhost:5000/api/network
```

## Logs

Network change operations are logged to `/chuckey/logs/update.log`:

```
[2025-11-16 01:38:19] === NETWORK SETTINGS CHANGE TRIGGERED ===
[2025-11-16 01:38:19] Network configuration: {"mode":"manual","ip":"172.16.1.150",...}
[2025-11-16 01:38:19] Applying network configuration: mode=manual
[2025-11-16 01:38:19] Using connection: Wired connection 1
[2025-11-16 01:38:19] Switching to manual mode: IP=172.16.1.150/24 Gateway=172.16.1.254
[2025-11-16 01:38:28] Manual configuration applied successfully
[2025-11-16 01:38:28] Network settings applied successfully
[2025-11-16 01:38:28] Network change trigger file cleaned up
```

## UI Implementation Checklist

- [ ] Add GET endpoint to fetch current network settings
- [ ] Add POST endpoint to apply network settings
- [ ] Implement input validation for IP, netmask, gateway
- [ ] Add mode toggle (DHCP/Manual) in UI
- [ ] Show/hide IP/netmask/gateway fields based on mode
- [ ] Display connection loss warning before applying changes
- [ ] Implement loading state during network change (15 second timeout)
- [ ] Handle success/error responses from backend
- [ ] Test both DHCP and Manual modes
- [ ] Test error cases (invalid IP, missing fields, etc.)
