#!/bin/bash
# Decrypt.sh - Wrapper script to call Decrypt.ps1
# Decrypts .Locked files created by SendCUIEmail

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for PowerShell
if ! command -v pwsh &> /dev/null; then
    echo -e "${RED}ERROR: PowerShell Core (pwsh) not found.${NC}"
    echo "Install with: brew install powershell"
    exit 1
fi

# Build file list
if [ $# -eq 0 ]; then
    # No arguments: decrypt all .Locked files in current directory
    echo -e "${YELLOW}No files specified. Decrypting all .Locked files in current directory...${NC}"

    FILES=()
    for f in *.Locked; do
        # Check if glob matched anything
        [ -e "$f" ] || continue
        # Skip directories
        [ -d "$f" ] && continue
        FILES+=("$f")
    done

    if [ ${#FILES[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No .Locked files found in current directory.${NC}"
        exit 1
    fi

    echo "Files to decrypt:"
    for f in "${FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
else
    FILES=("$@")
fi

# Call Decrypt.ps1
pwsh -NoProfile -File "$SCRIPT_DIR/Decrypt.ps1" "${FILES[@]}"
