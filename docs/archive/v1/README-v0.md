# CUI//SP-CTI//SP-EXPT - Encrypted Files - Decryption Instructions

> **CUI//SP-CTI//SP-EXPT (Controlled Technical Information, Export Controlled)**
> This document contains CUI handling instructions. Protect accordingly.

## Why You Received Password-Encrypted Files

This email uses password-based encryption rather than certificate-based encryption (S/MIME) because one of the following applies:

- You do not have a PIV/CAC smart card with email encryption certificate
- Your certificate was not accessible to the sender (different organization, no directory access)
- Your email client does not support S/MIME decryption
- This is one-time or infrequent communication where certificate exchange was not practical

When both parties have PIV/CAC, native S/MIME (Outlook Sign+Encrypt) is preferred. This tool uses AES-256 encryption via Windows CNG (Cryptography Next Generation), which is FIPS 140-2 validated when Windows FIPS mode is enabled (see [CMVP Certificate #4515](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4515)).

## Receiving the Password

**You will receive the password via a separate channel.** Per NIST SP 800-63B, passwords for encrypted files should be transmitted out-of-band (not in the same email as the encrypted files).

**Approved channels:**
| Method | Why It's Approved |
|--------|-------------------|
| Phone call (PSTN landline) | Proves possession of phone number |
| SMS text message | Proves possession of device/SIM |
| In-person | Direct verification |
| S/MIME encrypted email | Password protected by asymmetric encryption |

**Not approved:** Unencrypted email (even if sent separately) does not meet out-of-band requirements.

**References:**
- [NIST SP 800-63B §5.1.3](https://pages.nist.gov/800-63-3/sp800-63b.html#-513-out-of-band-devices) - Out-of-band authenticator requirements
- [NIST SP 800-171 §3.13.8](https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final) - CUI transmission protection
- [32 CFR Part 2002](https://www.ecfr.gov/current/title-32/subtitle-B/chapter-XX/part-2002) - CUI handling requirements

## Encrypted Files

- `AGENTS.md.Locked`

## How to Decrypt (Windows PowerShell)

### Option 1: One-Liner (Copy & Paste)

Open **PowerShell** (Start Menu → type "PowerShell" → Enter), then paste this command:

```powershell
$f=Read-Host "File";$p=Read-Host "Password" -AsSecureString;$d=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$d[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$d[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($d,32,$d.Length-32);[IO.File]::WriteAllBytes($f-replace'\.Locked$','',$c);Write-Host "Decrypted:"($f-replace'\.Locked$','')
```

When prompted:
1. Enter the full path to the .Locked file (e.g., `C:\Downloads\Document.pdf.Locked`)
2. Enter the password

### Option 2: Step-by-Step Script

Save this as `Decrypt.ps1` and run it, or paste line-by-line:

```powershell
# Decrypt a .Locked file
# Usage: Change $filePath to your file, then run

$filePath = "C:\Path\To\YourFile.ext.Locked"  # <-- CHANGE THIS

# Prompt for password
$securePassword = Read-Host "Enter decryption password" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

# Read encrypted file
$data = [System.IO.File]::ReadAllBytes($filePath)

# Extract salt (first 16 bytes) and IV (next 16 bytes)
$salt = $data[0..15]
$iv = $data[16..31]
$ciphertext = $data[32..($data.Length - 1)]

# Derive key using PBKDF2
$keyDeriver = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
    $password, $salt, 100000, "SHA256"
)
$key = $keyDeriver.GetBytes(32)

# Decrypt using AES-256-CBC
$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Mode = "CBC"
$aes.Padding = "PKCS7"
$aes.Key = $key
$aes.IV = $iv

$decryptor = $aes.CreateDecryptor()
$plainBytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)

# Write decrypted file (removes .Locked extension)
$outputPath = $filePath -replace '\.Locked$', ''
[System.IO.File]::WriteAllBytes($outputPath, $plainBytes)

Write-Host "Decrypted successfully: $outputPath" -ForegroundColor Green

# Cleanup
$aes.Dispose()
$keyDeriver.Dispose()
```

## Technical Details

| Parameter | Value | Standard |
|-----------|-------|----------|
| Encryption | AES-256-CBC | FIPS 197, FIPS 140-2 |
| Key Derivation | PBKDF2-HMAC-SHA256 | NIST SP 800-132 |
| Iterations | 100,000 | NIST SP 800-132 minimum: 10,000 |
| Salt | 128-bit random (unique per file) | NIST SP 800-132 |
| IV | 128-bit random (unique per file) | NIST SP 800-38A |

**File Format**: Each `.Locked` file contains: Salt (16 bytes) + IV (16 bytes) + Ciphertext

**Security Note**: Salt and IV are cryptographically random and unique for each encrypted file. They are automatically extracted from the file during decryption---you only need the password.

**Compliance**: This encryption uses algorithms approved under FIPS 197 (AES) and NIST SP 800-132 (PBKDF2). For full NIST SP 800-171 §3.13.11 compliance, ensure Windows FIPS mode is enabled on systems handling CUI.

## Troubleshooting

- **"Access denied"**: Run PowerShell as Administrator, or save file to Desktop first
- **"Path not found"**: Use full path with drive letter (e.g., `C:\Users\...`)
- **Garbled output**: Wrong password - try again
- **Script won't run**: Execution policy - use the one-liner instead, or run:
  `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

---
*Encrypted with SendCUIEmail - 2026-01-22 06:27*