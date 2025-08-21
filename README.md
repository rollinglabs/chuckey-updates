# Chuckey Updates

This repository contains versioned update definitions for Chuckey devices.

## 📦 Folders

- `stable/` – Latest production-ready release

Each folder includes:
- `VERSION` – Current version identifier
- `docker-compose.yml` – Services to run (e.g. Chuckey UI)
- `update.sh` – Script to pull and apply the update

## 🚀 Update Process (on-device)

Chuckey UI:
1. Checks this repo for a newer version
2. If found, downloads `update.sh` and runs it
3. Pulls new Docker image(s), restarts, and updates local version marker

## 🔐 Example Usage

From the Chuckey device:

```bash
curl -sSL https://raw.githubusercontent.com/rollinglabs/chuckey-updates/main/stable/update.sh | bash