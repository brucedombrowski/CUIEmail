#!/bin/bash
# SendCUIEmail - Stage Release Script
# Prepares a release for review before publishing
# Does NOT commit, tag, or push - use publish-release.sh for that

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
VERSION=""
SKIP_TESTS=false

print_usage() {
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Arguments:"
    echo "  version        Version number (e.g., 0.7.0)"
    echo ""
    echo "Options:"
    echo "  --skip-tests   Skip running tests"
    echo "  --help         Show this help message"
    echo ""
    echo "What this script does:"
    echo "  1. Updates version in CHANGELOG.md (moves Unreleased to new version)"
    echo "  2. Updates version in Quick-Start Guide PDF"
    echo "  3. Recompiles documentation PDFs"
    echo "  4. Runs test suite"
    echo "  5. Shows summary of changes for review"
    echo ""
    echo "After review, run: ./publish-release.sh <version>"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo -e "${RED}Unexpected argument: $1${NC}"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo -e "${RED}ERROR: Version number required${NC}"
    print_usage
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Invalid version format. Use semver (e.g., 0.7.0)${NC}"
    exit 1
fi

TAG="v$VERSION"
TODAY=$(date +%Y-%m-%d)

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  SendCUIEmail - Stage Release${NC}"
echo -e "${CYAN}  Version: $VERSION${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Tag $TAG already exists.${NC}"
    exit 1
fi

# Step 1: Update CHANGELOG.md
echo -e "${CYAN}[1/4] Updating CHANGELOG.md...${NC}"
if grep -q "## \[Unreleased\]" CHANGELOG.md; then
    # Check if there are actual changes under Unreleased
    UNRELEASED_CONTENT=$(sed -n '/## \[Unreleased\]/,/## \[/p' CHANGELOG.md | head -n -1 | tail -n +2)

    if echo "$UNRELEASED_CONTENT" | grep -q "^### "; then
        # There are changes - add new version header after Unreleased section
        # This is complex with sed, so we'll use a simple approach
        echo -e "  ${YELLOW}Note: CHANGELOG.md has Unreleased content${NC}"
        echo -e "  ${YELLOW}Please manually move Unreleased items to [$VERSION] - $TODAY${NC}"
    else
        echo -e "  ${YELLOW}No changes under [Unreleased] section${NC}"
    fi
else
    echo -e "  ${YELLOW}No [Unreleased] section found${NC}"
fi

# Step 2: Run tests
echo ""
if [ "$SKIP_TESTS" = true ]; then
    echo -e "${CYAN}[2/3] Skipping tests (--skip-tests)${NC}"
else
    echo -e "${CYAN}[2/3] Running tests...${NC}"
    if [ -x "$SCRIPT_DIR/test.sh" ]; then
        if ! "$SCRIPT_DIR/test.sh" --version "$VERSION"; then
            echo -e "${RED}ERROR: Tests failed. Fix issues before releasing.${NC}"
            exit 1
        fi
    else
        echo -e "  ${YELLOW}test.sh not found or not executable${NC}"
    fi
fi

# Step 3: Show summary
echo ""
echo -e "${CYAN}[3/3] Release staging summary...${NC}"
echo ""

# Show git status
echo -e "${YELLOW}Modified files:${NC}"
git status --short

echo ""
echo -e "${YELLOW}Files to be included in release:${NC}"
echo "  - Encrypt.bat, Encrypt.ps1"
echo "  - Decrypt.bat, Decrypt.ps1"
echo "  - Open_PowerShell.bat, LICENSE"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Release $VERSION Staged${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the changes above"
echo "  2. Make any manual CHANGELOG.md updates if needed"
echo "  3. Run: ${CYAN}./publish-release.sh $VERSION${NC}"
echo ""
