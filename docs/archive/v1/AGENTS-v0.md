# AGENTS.md

Instructions for AI agents working with this repository.

## Project Overview

SendCUIEmail is a Windows tool for encrypting files before sending via email. Designed for CUI (Controlled Unclassified Information) transmission when email certificate exchange isn't possible. Recipients decrypt using built-in PowerShell commands - no executables required.

## Target Environment

**Primary: Windows 11** (designed for constrained IT environments):
- CIS Windows 11 Enterprise baseline
- DISA STIG Windows 11 baseline
- Microsoft Security Baseline

**Development/Testing: Cross-Platform**
- PowerShell Core 7+ on macOS and Linux
- Core encryption/decryption fully functional
- Outlook .msg generation Windows-only (gracefully skipped on other platforms)
- See `Decisions/DM-2026-001_cross_platform_support.tex` for rationale

## Compliance Standards

- **FIPS 140-2**: AES-256-CBC encryption (validated algorithm)
- **NIST SP 800-132**: PBKDF2-HMAC-SHA256 key derivation (100,000 iterations)
- **NIST SP 800-171**: CUI handling requirements
- **32 CFR Part 2002**: CUI marking requirements

## File Structure

```
SendCUIEmail/
├── Encrypt.bat          # Drag-and-drop encryption launcher (Windows)
├── Encrypt.ps1          # Main PowerShell encryption script (cross-platform)
├── Decrypt.bat          # Drag-and-drop decryption launcher (Windows)
├── Decrypt.ps1          # PowerShell decryption script (cross-platform)
├── Test.bat             # Round-trip test launcher (Windows)
├── Test.ps1             # Automated test suite (cross-platform)
├── test.sh              # Test launcher (macOS/Linux)
├── release.sh           # Release packaging script
├── README.md            # User documentation
├── AGENTS.md            # This file
├── LICENSE              # MIT License
├── .gitignore           # Git ignore rules
├── Decisions/
│   ├── DM-2026-001_cross_platform_support.tex  # Cross-platform decision
│   ├── DM-2026-001_cross_platform_support.pdf
│   ├── DM-2026-002_file_size_limit.tex         # 10MB file size limit decision
│   └── DM-2026-002_file_size_limit.pdf
├── testdata/
│   ├── README.md            # Test data documentation
│   ├── generate_testdata.sh # Script to generate test files
│   └── (generated files)    # small_text.txt, binary_sample.bin, etc.
└── examples/
    └── test_document.tex    # LaTeX test document (compile to PDF for testing)
```

## File Size Policy

**Maximum supported attachment: 10 MB**

Files larger than 10 MB should use alternative secure transfer methods. See `Decisions/DM-2026-002_file_size_limit.pdf` for rationale.

## Architecture

### Sender-Side Workflow

```
User drags files → Encrypt.bat → Encrypt.ps1
                                    ↓
                          1. Select CUI category
                          2. Enter password (twice)
                          3. Encrypt each file
                          4. Generate README.md
                          5. Generate .msg file (if Outlook available)
                                    ↓
                          Output: *.Locked, README.md, CUI_Email_*.msg
```

### Recipient-Side Workflow

```
Receive email → Open README.md → Copy PowerShell one-liner
                                    ↓
                          Run in PowerShell → Enter file path → Enter password
                                    ↓
                          Decrypted file (original extension restored)
```

### Encrypted File Format

```
┌──────────────┬──────────────┬────────────────────────┐
│ Salt (16 B)  │ IV (16 B)    │ Ciphertext (variable)  │
└──────────────┴──────────────┴────────────────────────┘
```

- **Salt**: Random 128-bit value for key derivation
- **IV**: Random 128-bit initialization vector for AES
- **Ciphertext**: AES-256-CBC encrypted file contents with PKCS7 padding

## Code Components

### Encrypt.bat

Entry point for drag-and-drop operation:
- Checks PowerShell availability
- Builds argument list from dropped files
- Calls Encrypt.ps1 with execution policy bypass

### Encrypt.ps1

Main encryption script with these functions:

#### Configuration
```powershell
$ITERATIONS = 100000  # PBKDF2 iterations (NIST SP 800-132)
$SALT_SIZE = 16       # 128 bits
$KEY_SIZE = 32        # 256 bits for AES-256
$IV_SIZE = 16         # 128 bits (AES block size)
```

#### CUI Categories (32 CFR Part 2002)
```powershell
$CUI_CATEGORIES = @{
    "1" = "CUI"           # Basic CUI
    "2" = "CUI//SP-CTI"   # Controlled Technical Information
    "3" = "CUI//SP-EXPT"  # Export Controlled
    "4" = "CUI//SP-PRVCY" # Privacy
    "5" = "CUI//SP-PROPIN"# Proprietary Business Information
}
```

#### Functions

| Function | Purpose |
|----------|---------|
| `Write-Banner` | Display startup banner |
| `Get-CUICategory` | Interactive CUI category selection |
| `Get-SecurePassword` | Password input with confirmation |
| `Encrypt-File` | Core AES-256-CBC encryption |
| `Get-FilesToEncrypt` | Resolve file/folder paths |
| `Generate-ReadMe` | Create decryption instructions |
| `Generate-OutlookEmail` | Create .msg with attachments |

### Decrypt.ps1

Decryption script with these functions:

| Function | Purpose |
|----------|---------|
| `Write-Banner` | Display startup banner |
| `Get-Password` | Single password input |
| `Decrypt-File` | Core AES-256-CBC decryption |
| `Get-FilesToDecrypt` | Resolve .Locked file paths |

Features:
- Validates .Locked extension
- Checks minimum file size
- Prompts before overwriting existing files
- Catches cryptographic exceptions (wrong password)

### Test.ps1

Automated test suite with:

| Function | Purpose |
|----------|---------|
| `Encrypt-TestFile` | Standalone encryption for testing |
| `Decrypt-TestFile` | Standalone decryption for testing |
| `Get-FileHash256` | SHA-256 hash for verification |
| `Test-RoundTrip` | Full encrypt/delete/decrypt/verify cycle |
| `Test-WrongPassword` | Verify wrong password rejection |

### Decryption One-Liner

The README.md includes a compact PowerShell one-liner for decryption:

```powershell
$f=Read-Host "File";$p=Read-Host "Password" -AsSecureString;$d=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$d[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$d[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($d,32,$d.Length-32);[IO.File]::WriteAllBytes($f-replace'\.Locked$','',$c);Write-Host "Decrypted:"($f-replace'\.Locked$','')
```

This one-liner:
1. Prompts for file path
2. Prompts for password (SecureString)
3. Reads encrypted file
4. Extracts salt (bytes 0-15) and IV (bytes 16-31)
5. Derives key using PBKDF2-HMAC-SHA256
6. Decrypts ciphertext
7. Writes output (removes .Locked extension)

## Building & Testing

### Prerequisites
- Windows 11 with PowerShell 5.1+
- Microsoft Outlook (optional, for .msg generation)

### Automated Test Suite

Run the comprehensive test suite:

```powershell
.\Test.bat
# Or directly:
powershell -ExecutionPolicy Bypass -File .\Test.ps1
```

The test suite verifies:
- Small text file encryption/decryption
- Empty file handling
- Single AES block (16 bytes)
- Multiple blocks (1 KB)
- Large files (100 KB random data)
- Binary content with null bytes
- Wrong password rejection

### Sample Test Document

A LaTeX test document is provided in `examples/test_document.tex`. Compile it to PDF:

```bash
cd examples
pdflatex test_document.tex
# Or: latexmk -pdf test_document.tex
```

The compiled PDF contains CUI markings and describes SendCUIEmail itself - perfect for testing the full workflow.

### Manual Testing

```powershell
# Compile test PDF (requires LaTeX)
cd examples && pdflatex test_document.tex && cd ..

# Test encryption
.\Encrypt.bat "examples\test_document.pdf"

# Test decryption
.\Decrypt.bat "examples\test_document.pdf.Locked"

# Or use the one-liner from generated README.md
```

### Test Scenarios

1. **Single file**: `.\Encrypt.bat document.pdf`
2. **Multiple files**: `.\Encrypt.bat file1.pdf file2.docx`
3. **Folder**: `.\Encrypt.bat "C:\Folder\To\Encrypt"`
4. **Verify decryption**: `.\Decrypt.bat document.pdf.Locked`
5. **Outlook .msg**: Verify attachments and CUI markings

## Common Tasks

### Adding a new CUI category

1. Add entry to `$CUI_CATEGORIES` hashtable in Encrypt.ps1
2. Update the selection prompt range in `Get-CUICategory`
3. Update this AGENTS.md

### Modifying encryption parameters

Key constants at top of Encrypt.ps1:
- `$ITERATIONS`: PBKDF2 iterations (must match decryption one-liner)
- `$KEY_SIZE`: AES key size in bytes
- `$SALT_SIZE`, `$IV_SIZE`: Must remain 16 for AES compatibility

**WARNING**: Changing these requires updating the decryption one-liner in `Generate-ReadMe`.

### Adding email body text

Modify the `Generate-OutlookEmail` function, specifically the `$mail.Body` string.

### Changing file extension

The `.Locked` extension is used in:
- `Encrypt-File`: Output path generation
- `Generate-ReadMe`: Decryption one-liner regex
- `Get-FilesToEncrypt`: Filter to exclude already-encrypted files

## Security Considerations

### Password Security
- Password entered as SecureString where possible
- Cleared from memory after use
- Minimum 8 characters enforced

### Key Derivation
- PBKDF2 with 100,000 iterations (exceeds NIST minimum of 10,000)
- SHA-256 hash function
- Random 128-bit salt per file

### Encryption
- AES-256-CBC (FIPS 140-2 approved)
- Random 128-bit IV per file
- PKCS7 padding

### Recommendations for Users
- Share password via separate channel (phone, text, in-person)
- Verify recipient authorization for CUI
- Document transmission per retention policy

## Dependencies

**PowerShell Built-ins Only** (no external modules):
- `System.Security.Cryptography.Aes`
- `System.Security.Cryptography.Rfc2898DeriveBytes`
- `System.Security.Cryptography.RandomNumberGenerator`

**Optional**:
- Microsoft Outlook COM (`Outlook.Application`) for .msg generation

## Related Projects

- [PDFSigner](https://github.com/brucedombrowski/PDFSigner) - Digital signature tool for PDFs
- Used together: Sign PDF, then encrypt for transmission

## Code Style

- PowerShell 5.1 compatible syntax
- Descriptive function and variable names
- Comment headers for major sections
- Clear error messages with color coding
