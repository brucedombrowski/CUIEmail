# Changelog

All notable changes to SendCUIEmail will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### v1.0.0 Target (Non-Technical User Release)
- Any UX improvements from developer beta feedback
- Production-ready for non-technical CUI handlers

## [0.17.3] - 2026-01-22

### Changed
- **VER Document REQ Traceability** - Verification document now maps directly to REQ IDs
  - Each section references actual REQ-1.1, REQ-2.1, etc. from REQ-2026-001
  - Summary table lists all 28 requirements with verification status
  - Grouped by category: Encryption, Key Derivation, RNG, Password, File Format, Platform

## [0.17.2] - 2026-01-22

### Fixed
- **Drag-Drop from Different Folders** - Fixed path handling for files dragged from other directories
  - Now properly resolves absolute paths for files from any location
  - Output always goes to same folder as source file (no output picker)

## [0.17.1] - 2026-01-22

### Fixed
- **File Picker Actually Works** - Removed .bat usage message that blocked file picker
  - Double-click now properly opens PowerShell with file picker dialog
  - .bat files no longer exit early when no arguments provided

## [0.17.0] - 2026-01-22

### Added
- **File Picker on Double-Click** - No files needed to start
  - Double-click `Encrypt.bat` or `Decrypt.bat` to open file picker dialog
  - Or drag files onto the .bat to skip the picker (still supported)
  - Makes the tool usable without command-line knowledge

### Changed
- **Simplified README.html** - Updated sender instructions
  - Steps reduced from 5 to 3
  - Clearly shows both double-click and drag-drop options
  - Removed outdated "Select or drag files" step

## [0.16.0] - 2026-01-22

### Added
- **Sender README** - `README.html` now included in release zip
  - Quick start guide for senders (encrypting files)
  - Step-by-step encryption and sending instructions
  - Password delivery compliance guidance
  - Troubleshooting section
  - Matches styling of recipient's `Decrypt_Instructions.html`

## [0.15.0] - 2026-01-22

### Changed
- **Data-Driven Traceability** - REQ PDF traceability table now generated from JSON
  - Added `trace` field to each requirement in JSON (e.g., "§5.1 Salt")
  - build-requirements-pdf.py generates traceability table dynamically
  - No more hardcoded requirement IDs in Python script
  - REQ document bumped to v1.1

## [0.14.0] - 2026-01-22

### Changed
- **VER Document Clarity** - Clearer version labeling in verification document
  - "Version Tested" renamed to "Software Version" (e.g., v0.14.0)
  - "Requirements" now shows REQ document version (e.g., REQ-2026-001 v1.0)
  - test.sh auto-extracts REQ version from JSON and updates VER document
  - Distinguishes software release version from requirements document version

## [0.13.0] - 2026-01-22

### Fixed
- **VER Document Version Sync** - Verification document now shows correct release version
  - `test.sh` accepts `--version` parameter for target version
  - `stage-release.sh` passes target version to test.sh
  - Previously VER doc would show previous release version

### Changed
- **VER→REQ Traceability** - VER-2026-001 now references REQ-2026-001
  - Document Information section includes Requirements reference
  - Links verification back to requirements JSON source

## [0.12.0] - 2026-01-22

### Changed
- **Email Body Improvements** - Better recipient experience
  - Digital Signature Request moved to top of email body
  - Fallback decryption instructions if HTML inaccessible (save file, run command)
  - PowerShell one-liner embedded directly in email body

## [0.11.0] - 2026-01-22

### Added
- **Requirements Documentation** - Formal cryptographic requirements in `Requirements/` folder
  - `REQ-2026-001_cryptographic_compliance.json` - JSON source of truth for 28 requirements
  - `build-requirements-pdf.py` - Generates LaTeX/PDF from JSON with version-stamped filenames
  - PDF includes source hash for JSON→PDF traceability
  - Requirements traced to specific sections in FIPS 197, NIST SP 800-38A, 800-132, 800-90A, 800-63B, FIPS 140-2, 32 CFR 2002
  - Standards table includes hyperlinks to authoritative NIST/CSRC sources

## [0.10.0] - 2026-01-22

### Changed
- **Simplified Regulatory Reference** - Email body now references only `32 CFR Part 2002`
  - Applies to both federal and non-federal systems (NIST SP 800-171/800-53 are implementation details)
- **HTML Banner Correction** - Decrypt_Instructions.html banner changed from CUI yellow to informational blue
  - Instructions file is not CUI; only the encrypted content is CUI
- **HTML Step 1 Added** - "Save the attached files" now first step in Quick Method
  - Recipients reminded to download .Locked files before decrypting
- **Repo Structure Cleanup** - Reorganized folders and removed redundant files
  - VER documents moved to `Verifications/` (separate from `Decisions/`)
  - Removed: QuickStart_Guide.pdf, examples/, old release.sh, .dist/

### Removed
- **QuickStart_Guide.pdf** - Eliminated from release zip
  - Redundant: tool guides senders interactively, HTML guides recipients

## [0.9.0] - 2026-01-22

### Added
- **HTML Decryption Instructions** - Replaced README.md with styled HTML file
  - `Decrypt_Instructions.html` with professional styling, CUI banner, color-coded steps
  - "Before You Start" FAQ section anticipating common recipient questions
  - Click-to-select code box for easy one-liner copy/paste
  - Compliance info as fine print in footer (AES-256, PBKDF2, NIST references)
  - Works offline with inline CSS, ~8 KB file size
  - Decision documented in DM-2026-007
- **Digital Signature Request** - CUI_Email now requests signed reply
  - Recipients with PIV/CAC asked to reply with digitally signed message
  - Supports compliance verification and trust establishment

### Changed
- Email subject line updated to reference `Decrypt_Instructions.html`
- Email body updated with new HTML file references
- All README.md references throughout codebase updated to HTML

### Documentation
- DM-2026-007: Recipient Instructions Format decision memo (LaTeX/PDF)

## [0.8.0] - 2026-01-22

### Added
- **Minimal Release Zip** - GitHub releases now include a downloadable zip for end users
  - `SendCUIEmail-vX.Y.Z.zip` attached to each release
  - Contains only essential files: Encrypt.bat, Encrypt.ps1, Decrypt.bat, Decrypt.ps1, Open_PowerShell.bat, LICENSE, QuickStart_Guide.pdf
  - End users download zip; developers clone full repo for source and tests
- **Release Workflow Improvements**
  - `publish-release.sh` now creates and attaches minimal zip automatically
  - Release notes distinguish between end user download and developer clone

## [0.7.2] - 2026-01-22

### Added
- **Open_PowerShell.bat** - Helper for recipients to launch PowerShell
  - Double-click to open PowerShell ready for decryption commands
  - Shows helpful message pointing to README.md

## [0.7.1] - 2026-01-22

### Changed
- **Recipient Decryption One-Liner** - Now uses file picker dialogs instead of typing paths
  - Open dialog to browse and select .Locked file
  - Save dialog to choose where to save decrypted file
  - No more path typing errors or System32 working directory issues
  - README.md instructions updated with new one-liner

## [0.7.0] - 2026-01-22

### Added
- **Sender Instructions in Email Drafts** - On-the-spot training to prevent leakage
  - CUI_Email: 5-step checklist before sending (add recipient, sign/encrypt, review attachments, test decryption, plan password delivery)
  - Password_Email: Clear delivery options (phone/SMS, S/MIME encrypt, or non-compliant warning)
  - Instructions must be deleted before sending as acknowledgement
- **Password Email Pre-Configured for Encryption** - S/MIME encryption enabled by default
  - Sets PR_SECURITY_FLAGS via MAPI to enable encryption automatically
  - Email body shows `[ENCRYPTION PRE-ENABLED]` or `[ENCRYPTION NOT PRE-SET]` status
  - Guides sender based on whether encryption was successfully configured
- **Organization Configuration Variables** - Customize for your organization when forking
  - `$ORG_NAME` - Organization name for branding
  - `$ORG_SUPPORT_CONTACT` - Support contact info for recipients
  - `$ORG_HANDLING_INSTRUCTIONS` - Additional handling requirements
  - `$MIN_PASSWORD_LENGTH` - Minimum password length (default 8)
  - `$DEFAULT_CUI_CATEGORY` - Default CUI category selection

## [0.6.1] - 2026-01-22

### Fixed
- **Empty Path Error** - Fixed "cannot bind argument to Path" error when encrypting files without full path
  - `Split-Path -Parent` returns empty for files like `document.pdf` vs `C:\path\document.pdf`
  - Now defaults to current directory when parent path is empty

### Added
- **Release Scripts** - New two-step release workflow
  - `stage-release.sh` - Prepares release (updates versions, compiles docs, runs tests)
  - `publish-release.sh` - Publishes release (commits, tags, pushes, creates GitHub release)

## [0.6.0] - 2026-01-21

### Added
- **Quick-Start Guide PDF** - 2-page guide in Docs/QuickStart_Guide.pdf
  - Part A: Encrypting Files (Sender) - 5 steps with color-coded boxes
  - Part B: Decrypting Files (Recipient) - 5 steps
  - S/MIME security hierarchy guidance (3 options for different scenarios)
  - Defense-in-depth rationale for combining S/MIME + file encryption
- **Auto-Generated Passphrase** - Press Enter at password prompt for secure passphrase
  - 4-word passphrase using cryptographic RNG (e.g., "beach-flame-ocean-pride")
  - Aligns with NIST SP 800-63B guidance: length > complexity
  - Type "new" to regenerate if desired
- **Output Folder Shown at Start** - Path displayed before encryption begins
- **Explorer Tip on Windows** - Shows `explorer.exe` command to open output folder

### Fixed
- Password delivery guidance now correctly lists S/MIME encrypted email as compliant

## [0.5.3] - 2026-01-21

### Changed
- **Password Entry UX** - Added hint "(Characters will not appear as you type)" before each password prompt
- **Output Location Display** - Output folder now shown prominently at top of file list with full paths
  - Yellow "Output folder:" label draws attention
  - All encrypted/decrypted files shown with full absolute paths
  - Easier for users to locate their files

### Documentation
- DM-2026-006: Beta readiness assessment with implementation plan

## [0.5.2] - 2026-01-21

### Added
- Cleanup reminder in console output warning users to delete .msg files after sending
- Password_Email warning highlighted in red (contains plaintext password)

## [0.5.1] - 2026-01-21

### Changed
- Password requirements now shown upfront before first prompt (not just after validation failure)
- Password transmission guidance now shows explicit compliance status:
  - `[COMPLIANT]` Phone call, SMS, in-person, S/MIME encrypted email
  - `[NOT COMPLIANT]` Unencrypted email - even if separate

## [0.5.0] - 2026-01-21

### Added
- **Multiple CUI Subcategory Selection** per 32 CFR Part 2002.20(a)(3)
  - Users can now select multiple subcategories (e.g., "1,2" for CTI+EXPT)
  - Generates proper compound markings like `CUI//SP-CTI//SP-EXPT`
  - Option 0 or empty input defaults to basic `CUI`

### Documentation
- DM-2026-005: Multiple CUI subcategory selection support decision memo

## [0.4.0] - 2026-01-21

### Added
- **Shell Wrapper Scripts** for macOS/Linux convenience
  - `Encrypt.sh` - Calls Encrypt.ps1 via pwsh
  - `Decrypt.sh` - Calls Decrypt.ps1 via pwsh
  - Both scripts encrypt/decrypt all files in directory when called with no arguments
  - Automatic filtering of scripts, .Locked files, and README from encryption

## [0.3.0] - 2026-01-21

### Documentation
- DM-2026-004: VER document numbering policy (stable IDs across releases)

## [0.2.0] - 2026-01-21

### Added
- **FIPS Mode Detection**
  - Automatic detection of Windows FIPS mode via registry key
  - Visual warning when FIPS mode is disabled
  - FIPS status displayed in completion summary

- **Cryptographic Compliance Verification**
  - VER-2026-001: Formal verification document for cryptographic compliance
  - Line-by-line code verification against NIST SP 800-132 and FIPS 197
  - Compliance summary matrix with verification status

- **Test Infrastructure**
  - Test output logging to `.builds/test_YYYYMMDD_HHMMSS.log`
  - Automatic PDF compilation of verification document when tests pass
  - Console output preserved while logging to file

### Changed
- Test script now produces verification PDF in `.builds/test/` directory
- Improved test output organization

### Documentation
- VER-2026-001_cryptographic_compliance.tex - Full cryptographic verification document
- DM-2026-004: VER document numbering policy (stable IDs across releases)
- LaTeX-formatted compliance verification with code listings
- Cross-referenced NIST/FIPS standards

## [0.1.0] - 2026-01-21

### Added
- **Core Encryption**
  - AES-256-CBC encryption (FIPS 140-2 compliant)
  - PBKDF2-HMAC-SHA256 key derivation (100,000 iterations per NIST SP 800-132)
  - 128-bit random salt and IV generation

- **CUI Support**
  - Five CUI category options per 32 CFR Part 2002
  - Proper CUI banners in email templates
  - Compliance documentation in decision memos

- **Email Integration (Windows)**
  - Outlook .msg draft generation for encrypted files
  - Separate password email draft with security warnings
  - CUI-compliant subject lines and body formatting

- **Recipient Experience**
  - README.md with PowerShell one-liner for decryption
  - Step-by-step decryption script included
  - NIST/FIPS compliance references in decryption instructions
  - No executable files sent - only PowerShell built-in APIs

- **Cross-Platform**
  - Windows PowerShell 5.1+ support (primary target)
  - PowerShell Core 7+ support for macOS/Linux (development/testing)
  - Graceful fallback when Outlook not available

- **Testing**
  - Automated test suite (`test.sh` / `Test.bat`)
  - Unit tests for encryption/decryption round-trip
  - Integration tests with full workflow
  - Test data generation scripts
  - `.builds/test/` output directory for inspection

- **Documentation**
  - Security hierarchy guidance (S/MIME vs SendCUIEmail)
  - NIST SP 800-63B compliance notes for password transmission
  - Decision memos (DM-2026-002 file size limit, DM-2026-003 password transmission)
  - File size limit guidance (10 MB maximum)

### Security
- Password confirmation required (prevents typos)
- Minimum 8-character password enforcement
- Password email includes compliance warnings
- Out-of-band password delivery guidance per NIST SP 800-63B
- S/MIME hybrid approach documented for organizations with PIV/CAC

### Dependencies
- Windows: PowerShell 5.1+ (built-in)
- macOS/Linux: PowerShell Core 7+ (optional)
- Microsoft Outlook (optional, for .msg generation)
