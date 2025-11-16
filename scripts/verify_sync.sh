#!/bin/bash
#
# verify_sync.sh - Verify synchronization between chuckey-updates and customize-image.sh
#
# This script ensures that embedded scripts in customize-image.sh match their
# source versions in chuckey-updates/stable/scripts/
#
# Usage: ./scripts/verify_sync.sh
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATES_DIR="$(dirname "$SCRIPT_DIR")"
SETUP_DIR="$(dirname "$UPDATES_DIR")/chuckey-setup"
CUSTOMIZE_SCRIPT="$SETUP_DIR/base-image/scripts/customize-image.sh"

# Check if customize-image.sh exists
if [[ ! -f "$CUSTOMIZE_SCRIPT" ]]; then
    echo -e "${RED}✗ Error: Cannot find customize-image.sh at:${NC}"
    echo "  Expected: $CUSTOMIZE_SCRIPT"
    echo ""
    echo -e "${YELLOW}Make sure chuckey-setup repository is cloned at:${NC}"
    echo "  $(dirname "$UPDATES_DIR")/chuckey-setup"
    exit 1
fi

echo -e "${BLUE}=== Chuckey Script Synchronization Verification ===${NC}"
echo ""
echo "Source: $UPDATES_DIR/stable/scripts/"
echo "Embedded: $CUSTOMIZE_SCRIPT"
echo ""

# Scripts to verify (use declare -A for associative array)
declare -A SCRIPTS
SCRIPTS["update_monitor.sh"]="MONITOREOF"
SCRIPTS["check_and_fetch.sh"]="CHECKFETCHEOF"
SCRIPTS["update.sh"]="UPDATEEOF"
SCRIPTS["get_stats.sh"]="GETSTATSEOF"

ERRORS=0
WARNINGS=0

# Verify each script
for script_name in "${!SCRIPTS[@]}"; do
    script="$script_name"
    heredoc_marker="${SCRIPTS[$script]}"
    source_file="$UPDATES_DIR/stable/scripts/$script"

    echo -e "${BLUE}Checking: $script${NC}"

    # Check if source file exists
    if [[ ! -f "$source_file" ]]; then
        echo -e "  ${RED}✗ Source file not found: $source_file${NC}"
        ((ERRORS++))
        continue
    fi

    # Extract embedded version from customize-image.sh
    # Pattern: cat > ... << 'MARKER'
    #          [content]
    #          MARKER

    # Find the heredoc section
    if ! grep -q "cat > .*$script.*<< '$heredoc_marker'" "$CUSTOMIZE_SCRIPT"; then
        echo -e "  ${YELLOW}⚠ Script not found in customize-image.sh (might not be embedded)${NC}"
        ((WARNINGS++))
        continue
    fi

    # Extract the heredoc content
    # Use awk to extract between the markers (skip first and last line)
    embedded_content=$(awk "/cat > .*$script.*<< '$heredoc_marker'/,/^$heredoc_marker\$/" "$CUSTOMIZE_SCRIPT" | \
                       sed '1d;$d')

    # Get source content
    source_content=$(cat "$source_file")

    # Create temp files for comparison
    temp_embedded=$(mktemp)
    temp_source=$(mktemp)
    echo "$embedded_content" > "$temp_embedded"
    echo "$source_content" > "$temp_source"

    # Compare
    if diff -q "$temp_embedded" "$temp_source" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ IN SYNC${NC}"
    else
        echo -e "  ${RED}✗ OUT OF SYNC${NC}"
        echo ""
        echo -e "${YELLOW}Differences:${NC}"
        diff -u "$temp_embedded" "$temp_source" || true
        echo ""
        ((ERRORS++))
    fi

    # Cleanup temp files
    rm -f "$temp_embedded" "$temp_source"
done

echo ""
echo -e "${BLUE}=== Summary ===${NC}"

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✅ All scripts are synchronized!${NC}"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) - some scripts may not be embedded${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) found - scripts are OUT OF SYNC${NC}"
    echo ""
    echo -e "${YELLOW}To fix:${NC}"
    echo "1. Determine which version is correct (usually chuckey-updates is source of truth)"
    echo "2. Update the heredoc section in customize-image.sh to match the source"
    echo "3. Run this script again to verify"
    echo ""
    echo -e "${YELLOW}See DEVELOPMENT.md for detailed synchronization instructions.${NC}"
    exit 1
fi
