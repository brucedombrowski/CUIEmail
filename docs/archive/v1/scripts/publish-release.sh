#!/bin/bash
# SendCUIEmail - Publish Release Script
# Commits, tags, pushes, and creates GitHub release
# Run stage-release.sh first to prepare the release

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
SKIP_CONFIRM=false

print_usage() {
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Arguments:"
    echo "  version        Version number (e.g., 0.7.0)"
    echo ""
    echo "Options:"
    echo "  -y, --yes      Skip confirmation prompts"
    echo "  --help         Show this help message"
    echo ""
    echo "What this script does:"
    echo "  1. Commits all staged changes with release message"
    echo "  2. Creates annotated git tag"
    echo "  3. Pushes commits and tag to remote"
    echo "  4. Creates GitHub release with release notes"
    echo ""
    echo "Run stage-release.sh first to prepare the release."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            SKIP_CONFIRM=true
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

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  SendCUIEmail - Publish Release${NC}"
echo -e "${CYAN}  Version: $VERSION${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Tag $TAG already exists.${NC}"
    echo "  If you need to re-release, delete the tag first:"
    echo "    git tag -d $TAG"
    echo "    git push origin :refs/tags/$TAG"
    exit 1
fi

# Check for changes to commit
echo -e "${CYAN}[1/7] Checking for changes...${NC}"
if git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "  ${YELLOW}No uncommitted changes found.${NC}"
    echo "  Did you run stage-release.sh first?"
    if [ "$SKIP_CONFIRM" = false ]; then
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    NEED_COMMIT=false
else
    echo -e "  Found changes to commit"
    git status --short
    NEED_COMMIT=true
fi

# Confirm before proceeding
echo ""
if [ "$SKIP_CONFIRM" = false ]; then
    echo -e "${YELLOW}This will:${NC}"
    if [ "$NEED_COMMIT" = true ]; then
        echo "  - Commit all changes with message 'Release v$VERSION'"
    fi
    echo "  - Create tag: $TAG"
    echo "  - Push to remote"
    echo "  - Delete old GitHub releases"
    echo "  - Create new GitHub release"
    echo ""
    read -p "Proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Step 2: Commit changes
echo ""
echo -e "${CYAN}[2/7] Committing changes...${NC}"
if [ "$NEED_COMMIT" = true ]; then
    git add -A
    git commit -m "Release v$VERSION"
    echo -e "  ${GREEN}Committed${NC}"
else
    echo -e "  ${YELLOW}Nothing to commit${NC}"
fi

# Step 3: Create tag
echo ""
echo -e "${CYAN}[3/7] Creating tag $TAG...${NC}"

# Extract release notes from CHANGELOG
RELEASE_NOTES=""
if [ -f "CHANGELOG.md" ]; then
    # Extract content between this version and the next version header
    RELEASE_NOTES=$(sed -n "/## \[$VERSION\]/,/## \[/p" CHANGELOG.md | head -n -1 | tail -n +2)
fi

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="Release $VERSION"
fi

git tag -a "$TAG" -m "Release $VERSION"
echo -e "  ${GREEN}Tag created${NC}"

# Step 4: Push to remote
echo ""
echo -e "${CYAN}[4/7] Pushing to remote...${NC}"
git push origin main
git push origin "$TAG"
echo -e "  ${GREEN}Pushed commits and tag${NC}"

# Step 5: Create minimal release zip
echo ""
echo -e "${CYAN}[5/7] Creating release zip...${NC}"
RELEASE_DIR="$SCRIPT_DIR/.release"
ZIP_NAME="SendCUIEmail-v$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

# Clean and create release directory
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/SendCUIEmail"

# Copy essential files for end users
RELEASE_FILES=(
    "Encrypt.bat"
    "Encrypt.ps1"
    "Decrypt.bat"
    "Decrypt.ps1"
    "Open_PowerShell.bat"
    "README.html"
    "LICENSE"
)

for file in "${RELEASE_FILES[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$RELEASE_DIR/SendCUIEmail/"
        echo -e "  + $file"
    else
        echo -e "  ${YELLOW}! $file not found${NC}"
    fi
done

# Create zip
cd "$RELEASE_DIR"
zip -r "$ZIP_NAME" SendCUIEmail > /dev/null
cd "$SCRIPT_DIR"
echo -e "  ${GREEN}Created: $ZIP_NAME${NC}"

# Step 6: Delete old GitHub releases (keep tags for history)
echo ""
echo -e "${CYAN}[6/7] Cleaning up old releases...${NC}"
if command -v gh &> /dev/null; then
    # Get list of old releases and delete them (tags are preserved)
    OLD_RELEASES=$(gh release list --json tagName -q '.[].tagName' 2>/dev/null)
    if [ -n "$OLD_RELEASES" ]; then
        for old_tag in $OLD_RELEASES; do
            echo -e "  Deleting release: $old_tag (tag preserved)"
            gh release delete "$old_tag" --yes 2>/dev/null || true
        done
        echo -e "  ${GREEN}Old releases removed (tags kept for history)${NC}"
    else
        echo -e "  No old releases to clean up"
    fi
fi

# Step 7: Create GitHub release
echo ""
echo -e "${CYAN}[7/7] Creating GitHub release...${NC}"
if command -v gh &> /dev/null; then
    # Build release notes for GitHub
    GH_NOTES="## What's New in v$VERSION

$RELEASE_NOTES

## Download

**For end users:** Download \`$ZIP_NAME\` below - contains everything needed to encrypt/decrypt files.

**For developers:** Clone the repository for full source, tests, and documentation.

See [CHANGELOG.md](CHANGELOG.md) for full details."

    gh release create "$TAG" \
        --title "v$VERSION" \
        --notes "$GH_NOTES" \
        "$ZIP_PATH"

    echo -e "  ${GREEN}GitHub release created with zip attachment${NC}"

    # Get release URL
    RELEASE_URL=$(gh release view "$TAG" --json url -q .url)
    echo ""
    echo -e "  Release URL: ${CYAN}$RELEASE_URL${NC}"
else
    echo -e "  ${YELLOW}GitHub CLI (gh) not installed. Skipping GitHub release.${NC}"
    echo "  Create manually at: https://github.com/brucedombrowski/SendCUIEmail/releases/new"
    echo "  Attach: $ZIP_PATH"
fi

# Cleanup release directory
rm -rf "$RELEASE_DIR"

# Summary
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Release $VERSION Published!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Summary:"
echo "  - Tag: $TAG"
echo "  - Commits pushed to main"
if command -v gh &> /dev/null; then
    echo "  - GitHub release created"
    echo "  - Release zip: $ZIP_NAME (attached to release)"
fi
echo ""
echo "End users: Download the zip from the GitHub release"
echo "Developers: Clone the full repo for source and tests"
echo ""
