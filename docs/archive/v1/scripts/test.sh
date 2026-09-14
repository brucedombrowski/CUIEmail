#!/bin/bash
# SendCUIEmail - Run encryption round-trip tests (macOS/Linux)
# Requires PowerShell Core: brew install powershell
# Usage: ./test.sh [--version X.Y.Z]

set -e

# Parse arguments
TARGET_VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Get script directory (needed early for log file)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create .builds directory and set up logging
mkdir -p "${SCRIPT_DIR}/.builds"
LOG_FILE="${SCRIPT_DIR}/.builds/test_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  SendCUIEmail - Test Suite (macOS/Linux)${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "Log file: ${LOG_FILE}"
echo ""

# Check for PowerShell Core
if ! command -v pwsh &> /dev/null; then
    echo -e "${RED}ERROR: PowerShell Core (pwsh) is not installed.${NC}"
    echo ""
    echo "Install with:"
    echo "  macOS:  brew install powershell"
    echo "  Ubuntu: sudo apt-get install -y powershell"
    echo "  See: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
    exit 1
fi

echo -e "${GREEN}Found PowerShell Core:${NC} $(pwsh --version)"
echo ""

# Ensure testdata exists
TESTDATA_DIR="${SCRIPT_DIR}/testdata"
if [ ! -f "${TESTDATA_DIR}/README.pdf" ]; then
    echo -e "${YELLOW}Generating test data files...${NC}"
    if [ -f "${TESTDATA_DIR}/generate_testdata.sh" ]; then
        "${TESTDATA_DIR}/generate_testdata.sh"
    else
        echo -e "${RED}ERROR: testdata/generate_testdata.sh not found${NC}"
        exit 1
    fi
    echo ""
fi

# Verify test files exist
echo -e "${CYAN}Verifying test data files...${NC}"
# Core test files (required)
REQUIRED_FILES=(
    "small_text.txt"
    "empty.txt"
    "binary_sample.bin"
    "medium_file.bin"
    "README.txt"
    "README.pdf"
)

# Large file test (optional, takes longer)
LARGE_FILES=(
    "large_file_10mb.bin"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "${TESTDATA_DIR}/${file}" ]; then
        SIZE=$(ls -lh "${TESTDATA_DIR}/${file}" | awk '{print $5}')
        echo -e "  ${GREEN}✓${NC} ${file} (${SIZE})"
    else
        echo -e "  ${RED}✗${NC} ${file} - MISSING"
        MISSING=1
    fi
done

# Check optional large files
for file in "${LARGE_FILES[@]}"; do
    if [ -f "${TESTDATA_DIR}/${file}" ]; then
        SIZE=$(ls -lh "${TESTDATA_DIR}/${file}" | awk '{print $5}')
        echo -e "  ${GREEN}✓${NC} ${file} (${SIZE}) [optional]"
    else
        echo -e "  ${YELLOW}○${NC} ${file} - not found (optional)"
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo -e "${RED}ERROR: Missing test files. Run: ./testdata/generate_testdata.sh${NC}"
    exit 1
fi
echo ""

# Run the PowerShell test suite (unit tests)
echo -e "${CYAN}[1/2] Running unit tests (Test.ps1)...${NC}"
echo ""
pwsh -NoProfile -File "${SCRIPT_DIR}/Test.ps1"
UNIT_EXIT=$?
echo ""

# Run file-based integration tests
echo -e "${CYAN}[2/2] Running full integration test (Encrypt.ps1 workflow)...${NC}"
echo ""

# Use .builds/test/ for output (overwrite each run)
BUILD_DIR="${SCRIPT_DIR}/.builds/test"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo -e "${CYAN}Test outputs will be saved to: .builds/test/${NC}"
echo ""

FILE_TESTS_PASSED=0
FILE_TESTS_FAILED=0
TEST_PASSWORD="TestPassword123!"
CUI_CATEGORY="1"  # Basic CUI

# Copy test files to build directory
echo -e "${CYAN}Copying test files to build directory...${NC}"
for file in "${REQUIRED_FILES[@]}"; do
    cp "${TESTDATA_DIR}/${file}" "${BUILD_DIR}/"
    echo "  Copied: ${file}"
done
echo ""

# Run encryption on test files using TestIntegration.ps1 (non-interactive)
echo -e "${CYAN}Running encryption on test files...${NC}"
echo ""

pwsh -NoProfile -File "${SCRIPT_DIR}/TestIntegration.ps1" \
    -OutputDir "$BUILD_DIR" \
    -Password "$TEST_PASSWORD" \
    -FileList "small_text.txt,empty.txt,binary_sample.bin"

ENCRYPT_EXIT=$?

echo ""
if [ $ENCRYPT_EXIT -eq 0 ]; then
    echo -e "${GREEN}Encrypt.ps1 completed successfully${NC}"
    ((FILE_TESTS_PASSED++))
else
    echo -e "${RED}Encrypt.ps1 failed with exit code $ENCRYPT_EXIT${NC}"
    ((FILE_TESTS_FAILED++))
fi

# Check for expected outputs
echo ""
echo -e "${CYAN}Checking generated files...${NC}"

# Check for .Locked files
for file in small_text.txt empty.txt binary_sample.bin; do
    if [ -f "${BUILD_DIR}/${file}.Locked" ]; then
        SIZE=$(ls -lh "${BUILD_DIR}/${file}.Locked" | awk '{print $5}')
        echo -e "  ${GREEN}✓${NC} ${file}.Locked (${SIZE})"
    else
        echo -e "  ${RED}✗${NC} ${file}.Locked - MISSING"
        ((FILE_TESTS_FAILED++))
    fi
done

# Check for Decrypt_Instructions.html
if [ -f "${BUILD_DIR}/Decrypt_Instructions.html" ]; then
    SIZE=$(ls -lh "${BUILD_DIR}/Decrypt_Instructions.html" | awk '{print $5}')
    echo -e "  ${GREEN}✓${NC} Decrypt_Instructions.html (${SIZE})"

    # Verify PowerShell one-liner is present
    if grep -q 'Rfc2898DeriveBytes' "${BUILD_DIR}/Decrypt_Instructions.html"; then
        echo -e "    ${GREEN}✓${NC} Contains PowerShell decryption one-liner"
    else
        echo -e "    ${RED}✗${NC} Missing PowerShell decryption one-liner"
        ((FILE_TESTS_FAILED++))
    fi
else
    echo -e "  ${RED}✗${NC} Decrypt_Instructions.html - MISSING"
    ((FILE_TESTS_FAILED++))
fi

# Check for .msg files (Windows/Outlook only)
MSG_FILES=$(ls "${BUILD_DIR}"/*.msg 2>/dev/null | wc -l | tr -d ' ')
if [ "$MSG_FILES" -gt 0 ]; then
    for msgfile in "${BUILD_DIR}"/*.msg; do
        SIZE=$(ls -lh "$msgfile" | awk '{print $5}')
        echo -e "  ${GREEN}✓${NC} $(basename "$msgfile") (${SIZE})"
    done
else
    echo -e "  ${YELLOW}○${NC} .msg files - Not generated (requires Windows + Outlook)"
    # Generate sample email body content for inspection
    echo -e "  ${CYAN}→${NC} Generating sample email content for inspection..."

    # Generate CUI_Email body
    cat > "${BUILD_DIR}/CUI_Email_SAMPLE.txt" << 'EMAILEOF'
================================================================================
SAMPLE: CUI_Email.msg body content (would be generated on Windows with Outlook)
================================================================================

Subject: CUI - Encrypted Files - See Decrypt_Instructions.html

Body:
--------------------------------------------------------------------------------
********************************************************************************
*                    SENDER INSTRUCTIONS - DELETE BEFORE SENDING               *
********************************************************************************

BEFORE YOU SEND THIS EMAIL:

1. ADD RECIPIENT
   - Enter the recipient's email address in the "To:" field
   - Verify they are authorized to receive CUI

2. SIGN AND ENCRYPT (if you have PIV/CAC)
   - Click "Sign" to prove this email came from you
   - Click "Encrypt" if you have the recipient's S/MIME certificate
   - S/MIME encryption adds transport protection on top of file encryption

3. REVIEW ATTACHMENTS
   - Verify the correct .Locked files are attached
   - Verify Decrypt_Instructions.html is attached
   - Remove any files that should not be sent

4. TEST DECRYPTION (recommended for first-time use)
   - Before sending, decrypt one file yourself using the HTML instructions
   - Confirms the password works and files are intact

5. PLAN PASSWORD DELIVERY
   - You must send the password via a SEPARATE channel
   - COMPLIANT: Phone call, SMS text, in-person, S/MIME encrypted email
   - NOT COMPLIANT: Unencrypted email (even if separate)

DELETE THIS ENTIRE SECTION BEFORE SENDING as acknowledgement that you have
reviewed these instructions.

********************************************************************************

CONTROLLED UNCLASSIFIED INFORMATION (CUI)
================================================================================

This email contains Controlled Unclassified Information (CUI) that requires
safeguarding per 32 CFR Part 2002.

ENCRYPTED FILES ATTACHED:
  - small_text.txt.Locked
  - empty.txt.Locked
  - binary_sample.bin.Locked
  - Decrypt_Instructions.html (Decryption Instructions)

DECRYPTION:
The attached files are encrypted using AES-256 (FIPS 140-2 compliant).
Please open Decrypt_Instructions.html in your browser for step-by-step decryption instructions.
You will need the password, which will be provided via separate communication.

HANDLING REQUIREMENTS:
- This information is CUI and must be protected accordingly
- Do not forward without authorization
- Store on approved systems only
- Destroy when no longer needed per retention requirements

DIGITAL SIGNATURE REQUEST:
If you have a PIV/CAC card or other email signing capability, please reply to
this email with a digitally signed message to confirm receipt. This helps
establish trust and supports compliance verification.

================================================================================
CONTROLLED UNCLASSIFIED INFORMATION (CUI)
--------------------------------------------------------------------------------

Attachments:
- small_text.txt.Locked
- empty.txt.Locked
- binary_sample.bin.Locked
- Decrypt_Instructions.html
================================================================================
EMAILEOF

    # Generate Password_Email body
    cat > "${BUILD_DIR}/Password_Email_SAMPLE.txt" << 'PWDEOF'
================================================================================
SAMPLE: Password_Email.msg body content (would be generated on Windows with Outlook)
================================================================================

Subject: RE: Encrypted Files - Additional Information

Body:
--------------------------------------------------------------------------------
********************************************************************************
*                    SENDER INSTRUCTIONS - DELETE BEFORE SENDING               *
********************************************************************************

CHOOSE ONE DELIVERY METHOD:

OPTION A: DO NOT SEND THIS EMAIL (Recommended)
   - Call the recipient and read them the password below
   - Or send via SMS text message
   - Or deliver in person
   - Then DELETE this .msg file

OPTION B: S/MIME ENCRYPT THIS EMAIL (If recipient has PIV/CAC)
   - This email is PRE-CONFIGURED to encrypt (requires recipient's certificate)
   - Enter recipient's email in "To:" field
   - Click "Sign" (proves it came from you)
   - Verify "Encrypt" is enabled (should be on by default)
   - Then send this email

OPTION C: UNENCRYPTED EMAIL - NOT COMPLIANT
   Sending this email unencrypted violates NIST SP 800-63B out-of-band
   requirements, even if sent separately from the encrypted files.

DELETE THIS INSTRUCTION SECTION BEFORE SENDING as acknowledgement that you
understand the compliance requirements.

********************************************************************************

DECRYPTION PASSWORD:

    TestPassword123!

================================================================================

AFTER DELIVERY:
- Delete this email/file (contains plaintext password)
- Confirm recipient successfully decrypted the files
- Document password transmission per your security procedures

================================================================================
--------------------------------------------------------------------------------

Attachments: None (password only)
================================================================================
PWDEOF

    echo -e "    ${GREEN}✓${NC} CUI_Email_SAMPLE.txt (sample body)"
    echo -e "    ${GREEN}✓${NC} Password_Email_SAMPLE.txt (sample body)"
fi

echo ""

# Verify decryption round-trip
echo -e "${CYAN}Verifying decryption round-trip...${NC}"
for file in small_text.txt empty.txt binary_sample.bin; do
    LOCKED_FILE="${BUILD_DIR}/${file}.Locked"
    DECRYPTED_FILE="${BUILD_DIR}/${file}.decrypted"
    ORIGINAL_FILE="${TESTDATA_DIR}/${file}"

    if [ ! -f "$LOCKED_FILE" ]; then
        continue
    fi

    echo -n "  Decrypting ${file}.Locked... "

    # Decrypt using the one-liner approach
    pwsh -NoProfile -Command "
        \$f = '$LOCKED_FILE'
        \$p = '$TEST_PASSWORD'
        \$d = [IO.File]::ReadAllBytes(\$f)
        \$k = [Security.Cryptography.Rfc2898DeriveBytes]::new(\$p, \$d[0..15], 100000, 'SHA256')
        \$a = [Security.Cryptography.Aes]::Create()
        \$a.Key = \$k.GetBytes(32)
        \$a.IV = \$d[16..31]
        \$c = \$a.CreateDecryptor().TransformFinalBlock(\$d, 32, \$d.Length-32)
        [IO.File]::WriteAllBytes('$DECRYPTED_FILE', \$c)
    " 2>/dev/null

    if [ ! -f "$DECRYPTED_FILE" ]; then
        echo -e "${RED}FAILED (decryption error)${NC}"
        ((FILE_TESTS_FAILED++))
        continue
    fi

    # Compare hashes
    if command -v sha256sum &> /dev/null; then
        ORIG_HASH=$(sha256sum "$ORIGINAL_FILE" | cut -d' ' -f1)
        DEC_HASH=$(sha256sum "$DECRYPTED_FILE" | cut -d' ' -f1)
    else
        ORIG_HASH=$(shasum -a 256 "$ORIGINAL_FILE" | cut -d' ' -f1)
        DEC_HASH=$(shasum -a 256 "$DECRYPTED_FILE" | cut -d' ' -f1)
    fi

    if [ "$ORIG_HASH" = "$DEC_HASH" ]; then
        echo -e "${GREEN}PASSED${NC}"
        ((FILE_TESTS_PASSED++))
    else
        echo -e "${RED}FAILED (hash mismatch)${NC}"
        ((FILE_TESTS_FAILED++))
    fi
done

echo ""

# Summary
TOTAL_PASSED=$FILE_TESTS_PASSED
TOTAL_FAILED=$FILE_TESTS_FAILED

if [ $UNIT_EXIT -ne 0 ]; then
    echo -e "${RED}Unit tests failed!${NC}"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Test Results Summary${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo "Unit tests (Test.ps1): $([ $UNIT_EXIT -eq 0 ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")"
echo "Integration tests: ${FILE_TESTS_PASSED} passed, ${FILE_TESTS_FAILED} failed"
echo ""

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Build Output (.builds/test/)${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
ls -la "$BUILD_DIR"/ 2>/dev/null
echo ""
echo -e "${CYAN}Files ready for recipient:${NC}"
ls "$BUILD_DIR"/*.Locked "$BUILD_DIR"/Decrypt_Instructions.html 2>/dev/null | xargs -I{} basename {}
echo ""
if [ -f "$BUILD_DIR/Decrypt_Instructions.html" ]; then
    echo -e "${CYAN}PowerShell one-liner from Decrypt_Instructions.html:${NC}"
    # Extract one-liner from HTML code-box div
    grep -o 'class="code-box"[^>]*>[^<]*' "$BUILD_DIR/Decrypt_Instructions.html" | sed 's/class="code-box"[^>]*>//' | head -1
    echo ""
fi

if [ $TOTAL_FAILED -eq 0 ]; then
    # Compile verification document if pdflatex is available
    VER_TEX="${SCRIPT_DIR}/Verifications/VER-2026-001_cryptographic_compliance.tex"
    if [ -f "$VER_TEX" ] && command -v pdflatex &> /dev/null; then
        echo ""
        echo -e "${CYAN}================================================${NC}"
        echo -e "${CYAN}  Compiling Verification Document${NC}"
        echo -e "${CYAN}================================================${NC}"
        echo ""

        pushd "${SCRIPT_DIR}/Verifications" > /dev/null

        # Get current git info for verification document
        GIT_COMMIT_FULL=$(git rev-parse HEAD)
        GIT_COMMIT_SHORT=$(git rev-parse --short HEAD)
        GIT_COMMIT_DATE=$(git log -1 --format="%ci")
        # Use target version if provided, otherwise extract from CHANGELOG.md
        if [ -n "$TARGET_VERSION" ]; then
            VERSION="$TARGET_VERSION"
        else
            VERSION=$(grep -E '^\#\# \[[0-9]+\.[0-9]+\.[0-9]+\]' "${SCRIPT_DIR}/CHANGELOG.md" | head -1 | sed 's/.*\[\([0-9.]*\)\].*/\1/')
        fi

        # Extract REQ version from JSON
        REQ_VERSION=$(grep '"version"' "${SCRIPT_DIR}/Requirements/REQ-2026-001_cryptographic_compliance.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

        echo "  Updating verification document with current commit info..."
        echo "    Software: v${VERSION}"
        echo "    Requirements: REQ-2026-001 v${REQ_VERSION}"
        echo "    Commit: ${GIT_COMMIT_SHORT}"

        # Update version and commit info in .tex file using sed
        # Title page version
        sed -i.bak "s/SendCUIEmail v[0-9.]*$/SendCUIEmail v${VERSION}/" VER-2026-001_cryptographic_compliance.tex
        # Document info table - Requirements version
        sed -i.bak "s/Requirements:} & REQ-2026-001 v[0-9.]*/Requirements:} \& REQ-2026-001 v${REQ_VERSION}/" VER-2026-001_cryptographic_compliance.tex
        # Document info table - Software version
        sed -i.bak "s/Software Version:} & v[0-9.]*/Software Version:} \& v${VERSION}/" VER-2026-001_cryptographic_compliance.tex
        sed -i.bak "s/Git Commit:} & \\\\texttt{[a-f0-9]*}/Git Commit:} \& \\\\texttt{${GIT_COMMIT_FULL}}/" VER-2026-001_cryptographic_compliance.tex
        sed -i.bak "s/Commit Date:} & [0-9-]* [0-9:]* [-+][0-9]*/Commit Date:} \& ${GIT_COMMIT_DATE}/" VER-2026-001_cryptographic_compliance.tex
        # Test verification section
        sed -i.bak "s/performed on commit \\\\texttt{[a-f0-9]*}/performed on commit \\\\texttt{${GIT_COMMIT_SHORT}}/" VER-2026-001_cryptographic_compliance.tex
        # Conclusion
        sed -i.bak "s/SendCUIEmail v[0-9.]* (commit \\\\texttt{[a-f0-9]*})/SendCUIEmail v${VERSION} (commit \\\\texttt{${GIT_COMMIT_SHORT}})/" VER-2026-001_cryptographic_compliance.tex
        # Footer
        sed -i.bak "s/Verified against commit:} \\\\texttt{[a-f0-9]*}/Verified against commit:} \\\\texttt{${GIT_COMMIT_FULL}}/" VER-2026-001_cryptographic_compliance.tex
        rm -f VER-2026-001_cryptographic_compliance.tex.bak

        # Run pdflatex twice for cross-references
        echo -n "  Compiling VER-2026-001... "
        if pdflatex -interaction=nonstopmode VER-2026-001_cryptographic_compliance.tex > /dev/null 2>&1 && \
           pdflatex -interaction=nonstopmode VER-2026-001_cryptographic_compliance.tex > /dev/null 2>&1; then
            echo -e "${GREEN}Done${NC}"

            # Clean up auxiliary files
            rm -f VER-2026-001_cryptographic_compliance.aux \
                  VER-2026-001_cryptographic_compliance.log \
                  VER-2026-001_cryptographic_compliance.out \
                  VER-2026-001_cryptographic_compliance.toc 2>/dev/null

            # Copy PDF to .builds
            cp VER-2026-001_cryptographic_compliance.pdf "${BUILD_DIR}/"
            echo -e "  ${GREEN}✓${NC} VER-2026-001_cryptographic_compliance.pdf"
        else
            echo -e "${YELLOW}Failed (check LaTeX installation)${NC}"
        fi

        popd > /dev/null
    elif [ -f "$VER_TEX" ]; then
        echo ""
        echo -e "${YELLOW}  Skipping verification PDF (pdflatex not installed)${NC}"
    fi

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}================================================${NC}"
    exit 0
else
    echo -e "${RED}================================================${NC}"
    echo -e "${RED}  SOME TESTS FAILED${NC}"
    echo -e "${RED}================================================${NC}"
    exit 1
fi
