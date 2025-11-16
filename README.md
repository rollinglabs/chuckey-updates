# Chuckey Updates

This repository contains versioned update definitions and scripts for Chuckey devices.

## 📦 Repository Structure

```
chuckey-updates/
├── stable/
│   ├── manifest.json           # Version manifest with file hashes
│   ├── docker-compose.yml      # Container definitions
│   └── scripts/
│       ├── check_and_fetch.sh  # Auto-update checker (runs on device)
│       ├── update.sh           # Update orchestrator
│       ├── update_monitor.sh   # inotify-based trigger monitor
│       └── get_stats.sh        # System stats collector
└── build_manifest.sh           # Manifest builder (dev use)
```

## 🔄 Update System

### Manifest-Based Updates

All updates are controlled by `stable/manifest.json`:
- **Version Tracking**: System version, component versions (chuckey-ui, unifi-controller)
- **File Integrity**: SHA256 hashes for all managed files
- **Self-Update**: Scripts can update themselves when newer versions are available

### Update Types

**App Updates (Container Images)**
- Pulls latest Docker images (chuckey-ui, unifi-controller)
- Restarts containers with new images
- Faster, less disruptive (~30-60 seconds)

**System Updates (Full Stack)**
- Updates docker-compose.yml and all scripts
- Verifies file integrity with SHA256 hashes
- Restarts entire container stack
- More comprehensive (~2-3 minutes)

### Auto-Update Scheduler

Chuckey devices include a built-in auto-update scheduler (chuckey-ui v0.9.66+):
- **Configurable Frequencies**: Separate schedules for app and system updates
- **Randomized Jitter**: 0-30 minute random delay prevents thundering herd problem
- **Background Thread**: Checks every 5 minutes for due updates
- **Trigger File Pattern**: Creates `/chuckey/data/update_{apps|system}_immediate` files
- **inotify Integration**: `update_monitor.sh` service detects triggers and executes updates

### Update Process (Automatic)

1. **Scheduler** (in chuckey-ui) determines update is due
2. **Trigger File** created in `/chuckey/data/`
3. **Monitor Service** (`update_monitor.sh`) detects trigger via inotify
4. **Check & Fetch** (`check_and_fetch.sh`) downloads manifest and verifies files
5. **Update Script** (`update.sh`) applies changes and restarts containers

### Update Process (Manual)

Via Chuckey UI dashboard:
1. User clicks "Check for App Updates" or "Check for System Updates"
2. UI creates trigger file immediately
3. Same automated flow executes

Or via command line:

```bash
# Manual app update
/chuckey/scripts/check_and_fetch.sh

# Force update regardless of version
/chuckey/scripts/check_and_fetch.sh --force
```

## 📚 Documentation

**For comprehensive development documentation, see:**
- **[DEVELOPMENT.md](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/DEVELOPMENT.md)** - Development workflows, script synchronization, testing procedures
- **[MANUFACTURING-SYSTEM.md](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/MANUFACTURING-SYSTEM.md)** - 3-phase manufacturing pipeline
- **[CLAUDE.md](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/CLAUDE.md)** - Complete project history and architecture

**Quick Links:**
- Script Synchronization Process: See [DEVELOPMENT.md - Script Synchronization](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/DEVELOPMENT.md#script-synchronization)
- Release Process: See [DEVELOPMENT.md - Release Process](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/DEVELOPMENT.md#release-process)
- Platform Compatibility: See [DEVELOPMENT.md - Platform Compatibility](https://github.com/rollinglabs/chuckey-setup/blob/main/docs/DEVELOPMENT.md#platform-compatibility)

## 🛠️ Development

### Building a New Manifest

```bash
# Run the interactive manifest builder
./build_manifest.sh

# Prompts for:
# - Version (e.g., v0.9.72)
# - Release date (auto-generated, or custom)
# - Description
# - Requires reboot? (y/N)
# - chuckey-ui version
# - unifi-controller version

# Automatically calculates SHA256 hashes for all files
```

### Release Process

1. Update files in `stable/` (docker-compose.yml, scripts, etc.)
2. Run `./build_manifest.sh` to generate new manifest.json
3. Commit and tag: `git tag -a v0.9.XX -m "Description"`
4. Push: `git push origin main && git push origin v0.9.XX`
5. Devices will detect and apply updates based on their schedules

### Manifest Format

```json
{
  "version": "v0.9.72",
  "release_date": "2025-10-29T04:00:00Z",
  "description": "Release description",
  "requires_reboot": false,
  "components": {
    "chuckey-ui": {
      "version": "v0.9.66",
      "description": "Component description"
    },
    "unifi-controller": {
      "version": "v9.5.21",
      "description": "Component description"
    }
  },
  "files": {
    "docker-compose.yml": {
      "path": "/chuckey/docker-compose.yml",
      "sha256": "..."
    }
  }
}
```

## 📊 Current Version

- **Manifest**: v0.9.72
- **chuckey-ui**: v0.9.66 (Customer setup wizard and auto-update scheduler)
- **unifi-controller**: v9.5.21 (Improve application backup and restore resiliency)

## 🔗 Related Repositories

- **[chuckey-ui](https://github.com/rollinglabs/chuckey-ui)**: Web dashboard and container orchestration
- **[chuckey-setup](https://github.com/rollinglabs/chuckey-setup)**: Armbian image builder with 3-phase manufacturing system

---

**Last Updated**: 2025-10-29
**Status**: ✅ Production Ready