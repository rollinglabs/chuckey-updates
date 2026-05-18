#!/bin/bash
# Migration 004: Fix dpkg interrupted state from docker.io upgrade; pre-seed Docker restart debconf answer
#
# unattended-upgrades ran on 2026-04-13 and upgraded docker.io (28.2.2->29.1.3).
# The docker.io postinst script asked "Should Docker be restarted?" interactively,
# but unattended-upgrades has no TTY. The prompt hung until killed, leaving dpkg
# mid-configure with 10 packages stuck in half-configured/unpacked state.
# This blocks all future apt upgrades with "dpkg was interrupted" errors.
#
# This migration:
#   1. Pre-seeds debconf so docker.io postinst never prompts interactively again
#   2. Runs dpkg --configure -a to complete all pending package configurations
#   3. Waits for Docker to be ready if dpkg restarted the daemon
#

set -euo pipefail

LOG="[migration-004]"

# Pre-seed debconf: auto-answer Docker's "restart daemon?" question.
# Prevents future docker.io upgrades via unattended-upgrades from hanging.
echo "$LOG Pre-seeding debconf for docker.io restart..."
echo "docker.io docker.io/restart boolean true" | debconf-set-selections

# Check if any packages are stuck (half-configured or unpacked-but-not-configured)
if ! dpkg --audit 2>&1 | grep -qE '(not yet configured|only half configured|half-configured)'; then
    echo "$LOG dpkg state is clean, nothing to configure"
    exit 0
fi

echo "$LOG Incomplete package configurations detected, running dpkg --configure -a..."
DEBIAN_FRONTEND=noninteractive dpkg --configure -a
echo "$LOG dpkg --configure -a complete"

# docker.io postinst may have restarted the Docker daemon.
# Wait for it to be ready before exiting so the rest of the update proceeds cleanly.
echo "$LOG Waiting for Docker daemon..."
for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "$LOG Docker is ready"
        exit 0
    fi
    sleep 1
done

echo "$LOG WARNING: Docker not ready after 30s"
