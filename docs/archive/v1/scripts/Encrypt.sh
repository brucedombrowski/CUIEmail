#!/bin/bash
# Encrypt.sh - Wrapper script to call Encrypt.ps1
# Encrypts files for secure CUI email transmission per NIST SP 800-171

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
    # No arguments: encrypt all files in current directory (excluding hidden, scripts, and common non-data files)
    echo -e "${YELLOW}No files specified. Encrypting all files in current directory...${NC}"

    FILES=()
    for f in *; do
        # Skip directories
        [ -d "$f" ] && continue
        # Skip hidden files
        [[ "$f" == .* ]] && continue
        # Skip scripts and config
        [[ "$f" == *.sh ]] && continue
        [[ "$f" == *.ps1 ]] && continue
        [[ "$f" == *.bat ]] && continue
        # Skip already encrypted files
        [[ "$f" == *.Locked ]] && continue
        # Skip README (we generate one)
        [[ "$f" == README.md ]] && continue
        [[ "$f" == README.txt ]] && continue

        FILES+=("$f")
    done

    if [ ${#FILES[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No files found to encrypt in current directory.${NC}"
        exit 1
    fi

    echo "Files to encrypt:"
    for f in "${FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
else
    FILES=("$@")
fi

# Call Encrypt.ps1
pwsh -NoProfile -File "$SCRIPT_DIR/Encrypt.ps1" "${FILES[@]}"
