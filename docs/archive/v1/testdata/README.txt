# SendCUIEmail

Encrypt files for secure email transmission when certificate exchange isn't possible. Designed for CUI (Controlled Unclassified Information) handling per NIST SP 800-171.

## Security Hierarchy

| Rank | Method | When to Use |
|------|--------|-------------|
| 1 | **S/MIME (PIV/CAC to PIV/CAC)** | Both parties have smart cards. Use Outlook's native Sign+Encrypt. **Gold standard.** |
| 2 | **SendCUIEmail + S/MIME password** | Recipient has PIV/CAC. S/MIME encrypt the password email. |
| 3 | **SendCUIEmail + out-of-band password** | No PIV/CAC. Share password via phone/SMS/in-person. |
| 4 | **SendCUIEmail + unencrypted email password** | **NOT COMPLIANT** - convenience only with warnings. |

## When to Use This Tool

**Use native S/MIME (don't need SendCUIEmail) when:**
- Both parties have PIV/CAC with valid certificates
- Recipient's certificate is accessible
- Regular communication with same recipients

**Use SendCUIEmail when:**
- Recipient does not have PIV/CAC card
- Recipient's certificate is not accessible (different organization)
- One-time or infrequent communication with external parties
- Recipient's email client does not support S/MIME
- Files need to be forwarded/stored on non-S/MIME systems

See [Decisions/DM-2026-003_password_transmission.pdf](Decisions/DM-2026-003_password_transmission.pdf) for full guidance.

## Features

- **FIPS 140-2 Compliant**: AES-256-CBC encryption with PBKDF2-HMAC-SHA256 key derivation
- **CUI Marking Support**: Built-in CUI category selection per 32 CFR Part 2002
- **No Dependencies**: Uses only built-in Windows PowerShell cryptography
- **Email Ready**: Generates Outlook .msg draft with proper CUI banners and attachments
- **Recipient Friendly**: Recipients decrypt with a single PowerShell command (no executables)

## Quick Start

### Encrypt Files

1. Drag files or folders onto `Encrypt.bat`
2. Select CUI category
3. Enter password (twice to confirm)
4. Send the generated files to recipient

**Output:**
- `*.Locked` - Encrypted files
- `README.md` - Decryption instructions for recipient
- `CUI_Email_*.msg` - Outlook draft with encrypted files (if Outlook installed)
- `Password_Email_*.msg` - Outlook draft with password (send separately or use alternate channel)

### Decrypt Files

Recipients paste this PowerShell one-liner (from the README.md you send them):

```powershell
$f=Read-Host "File";$p=Read-Host "Password" -AsSecureString;$d=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$d[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$d[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($d,32,$d.Length-32);[IO.File]::WriteAllBytes($f-replace'\.Locked$','',$c);Write-Host "Decrypted:"($f-replace'\.Locked$','')
```

Or use `Decrypt.bat` if they have the tool.

## Files

| File | Purpose |
|------|---------|
| `Encrypt.bat` | Drag-and-drop encryption launcher |
| `Encrypt.ps1` | Main encryption script |
| `Decrypt.bat` | Drag-and-drop decryption launcher |
| `Decrypt.ps1` | Decryption script |
| `Test.bat` | Run round-trip verification tests |
| `Test.ps1` | Test script |

## What Gets Sent to Recipient

**Email 1** (Encrypted Files):
- `OriginalName.ext.Locked` - Encrypted file(s)
- `README.md` - Decryption instructions

**Email 2** (Password) - Send separately, or better yet, use alternate channel:
- Password only (no attachments)

**NOT sent:**
- No `.exe` files
- No `.ps1` scripts
- No `.zip` bundles
- No `.bat` files

**Password Transmission Options (per NIST SP 800-63B):**

| Method | Compliant? | Notes |
|--------|------------|-------|
| Phone/SMS/in-person | Yes | True out-of-band channel |
| S/MIME encrypted email | Yes | Encrypt password email with recipient's PIV/CAC certificate |
| Unencrypted email | No | Even separate email is not compliant |

**Hybrid Approach:** If recipient has PIV/CAC, S/MIME encrypt the password email (click "Encrypt" in Outlook). The password is then protected by asymmetric encryption - only the recipient can decrypt it.

See [Decisions/DM-2026-003_password_transmission.pdf](Decisions/DM-2026-003_password_transmission.pdf) for full guidance.

## File Size Limit

**Maximum supported attachment size: 10 MB**

Files larger than 10 MB should not be sent via encrypted email due to:
- Email gateway size limits (typically 10-25 MB)
- Base64 encoding overhead (~33% size increase)
- Delivery reliability concerns
- Mailbox quota limitations

For larger files, use:
- Secure file transfer services (SFTP, approved cloud storage)
- FIPS 140-2 validated encrypted USB drives
- DoD SAFE, MilSuite, or similar approved platforms

See [Decisions/DM-2026-002_file_size_limit.pdf](Decisions/DM-2026-002_file_size_limit.pdf) for full rationale.

## Security

### Encryption Details

| Parameter | Value |
|-----------|-------|
| Algorithm | AES-256-CBC |
| Key Derivation | PBKDF2-HMAC-SHA256 |
| Iterations | 100,000 |
| Salt | 128-bit random |
| IV | 128-bit random |

### Compliance

- **FIPS 140-2**: AES-256-CBC is a FIPS-approved algorithm
- **NIST SP 800-132**: PBKDF2 key derivation meets NIST recommendations
- **NIST SP 800-171**: CUI handling requirements
- **32 CFR Part 2002**: CUI marking requirements

### CUI Categories Supported

1. `CUI` - Basic Controlled Unclassified Information
2. `CUI//SP-CTI` - Controlled Technical Information
3. `CUI//SP-EXPT` - Export Controlled
4. `CUI//SP-PRVCY` - Privacy
5. `CUI//SP-PROPIN` - Proprietary Business Information

## Testing

### Automated Tests

Run the test suite to verify encryption/decryption:

```bash
# Windows
.\Test.bat

# macOS/Linux
./test.sh
```

### Test Data Files

Pre-built test files are in `testdata/`:

| File | Size | Purpose |
|------|------|---------|
| `small_text.txt` | 138 B | Basic text file |
| `empty.txt` | 0 B | Edge case: empty file |
| `binary_sample.bin` | 1 KB | Binary with null bytes |
| `medium_file.bin` | 1 MB | Medium binary file |
| `large_file_10mb.bin` | 10 MB | Maximum size test |
| `README.pdf` | ~175 KB | Generated from README.md |
| `README.docx` | ~15 KB | Generated from README.md |
| `README.png` | ~200 KB | First page of README as image |
| `sample.xlsx` | ~5 KB | Excel spreadsheet format |

Generate test files (if missing):
```bash
./testdata/generate_testdata.sh
```

### Sample LaTeX Document

A LaTeX source document is in `examples/test_document.tex`. Compile to PDF:

```bash
cd examples
pdflatex test_document.tex
```

## Requirements

**Windows (Primary Target):**
- Windows 10/11
- PowerShell 5.1 or later (included with Windows)
- Microsoft Outlook (optional, for .msg generation)

**macOS/Linux (Development/Testing):**
- PowerShell Core 7+: `brew install powershell` (macOS) or see [Microsoft docs](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- Outlook .msg generation not available (gracefully skipped)
- Core encryption/decryption fully functional

## Usage Examples

### Single File
```
Encrypt.bat document.pdf
```

### Multiple Files
```
Encrypt.bat file1.pdf file2.docx file3.xlsx
```

### Entire Folder
```
Encrypt.bat "C:\Sensitive\Documents"
```

### Command Line (PowerShell)
```powershell
powershell -ExecutionPolicy Bypass -File Encrypt.ps1 "document.pdf"
```

## Troubleshooting

### "Script cannot be loaded" error
Run via the .bat file, or set execution policy:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Outlook .msg not generated
This is optional - Outlook must be installed. You can manually attach files to email.

### Decryption fails
- Verify password is correct
- Ensure file wasn't corrupted during transfer
- Check file has `.Locked` extension

## License

MIT License - See [LICENSE](LICENSE) file.

## Related Projects

- [PDFSigner](https://github.com/brucedombrowski/PDFSigner) - Digital signature tool for PDFs
