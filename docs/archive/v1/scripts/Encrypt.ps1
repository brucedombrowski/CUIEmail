#Requires -Version 5.1
<#
.SYNOPSIS
    Encrypts files for secure CUI email transmission per NIST SP 800-171.

.DESCRIPTION
    Encrypts files using FIPS 140-2 compliant AES-256-CBC with PBKDF2 key derivation.
    Outputs .Locked files, Decrypt_Instructions.html with decryption instructions, and optionally
    a .msg email file with proper CUI markings per 32 CFR Part 2002.

    Compliance:
    - FIPS 140-2: AES-256-CBC encryption
    - NIST SP 800-132: PBKDF2-HMAC-SHA256 key derivation (100,000 iterations)
    - NIST SP 800-171: CUI handling requirements
    - 32 CFR Part 2002: CUI marking requirements

    Cross-Platform:
    - Works on Windows PowerShell 5.1+ and PowerShell Core 7+ (macOS/Linux)
    - Outlook .msg generation only available on Windows with Outlook installed

.PARAMETER Path
    Files or folders to encrypt. Accepts multiple paths.

.EXAMPLE
    .\Encrypt.ps1 "Document.pdf"
    .\Encrypt.ps1 "C:\Folder\To\Encrypt"
    .\Encrypt.ps1 "File1.pdf" "File2.docx" "File3.xlsx"
#>

param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Path
)

# ============================================================================
# ORGANIZATION CONFIGURATION - Customize these for your organization
# ============================================================================
# These settings can be modified when forking for your organization.
# All other code should remain unchanged for compliance verification.

$ORG_NAME = ""                    # Your organization name (leave empty for generic)
                                  # Example: "ACME Corporation"

$ORG_SUPPORT_CONTACT = ""         # Support contact for recipients having trouble
                                  # Example: "IT Security: security@acme.com or x1234"

$ORG_HANDLING_INSTRUCTIONS = ""   # Additional handling instructions (appended to emails)
                                  # Example: "Per ACME Policy 12.3, retain for 7 years."

$MIN_PASSWORD_LENGTH = 8          # Minimum password length (8 is NIST minimum)
                                  # Increase if your organization requires longer

$DEFAULT_CUI_CATEGORY = 0         # Default CUI category when user presses Enter
                                  # 0 = Basic CUI, 1 = CTI, 2 = EXPT, 3 = PRVCY, 4 = PROPIN

# ============================================================================
# CRYPTOGRAPHIC CONFIGURATION - Do not modify (FIPS 140-2 / NIST SP 800-132)
# ============================================================================
$ITERATIONS = 100000  # PBKDF2 iterations (NIST SP 800-132 recommends minimum 10,000)
$SALT_SIZE = 16       # bytes (128 bits)
$KEY_SIZE = 32        # bytes (256 bits for AES-256)
$IV_SIZE = 16         # bytes (128 bits for AES block size)

# ============================================================================
# DECRYPTION ONE-LINER - Single source of truth for Decrypt_Instructions.html and Password_Email
# ============================================================================
# This PowerShell one-liner is included in both Decrypt_Instructions.html and Password_Email.
# Uses file picker dialogs for ease of use. DO NOT MODIFY unless you understand
# the cryptographic operations (must match Encrypt-File function).
$DECRYPTION_ONELINER = 'Add-Type -AssemblyName System.Windows.Forms;$o=New-Object System.Windows.Forms.OpenFileDialog;$o.Title="Select .Locked file to decrypt";$o.Filter="Locked files (*.Locked)|*.Locked|All files (*.*)|*.*";if($o.ShowDialog()-eq''OK''){$f=$o.FileName;$p=Read-Host "Password" -AsSecureString;$b=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$b[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$b[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($b,32,$b.Length-32);$s=New-Object System.Windows.Forms.SaveFileDialog;$s.Title="Save decrypted file as";$s.FileName=[IO.Path]::GetFileName(($f-replace''\.Locked$'',''''));$s.InitialDirectory=[IO.Path]::GetDirectoryName($f);if($s.ShowDialog()-eq''OK''){[IO.File]::WriteAllBytes($s.FileName,$c);Write-Host "Decrypted: $($s.FileName)" -ForegroundColor Green}}'

# Platform detection
$IsWindowsPlatform = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows

# FIPS mode detection (Windows only)
function Test-FIPSMode {
    if (-not $IsWindowsPlatform) {
        # FIPS mode check only applies to Windows
        return @{
            Enabled = $false
            Applicable = $false
            Message = "FIPS mode check not applicable (non-Windows platform)"
        }
    }

    try {
        $fipsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy"
        $fipsValue = Get-ItemProperty -Path $fipsKey -Name "Enabled" -ErrorAction Stop
        $enabled = $fipsValue.Enabled -eq 1

        return @{
            Enabled = $enabled
            Applicable = $true
            Message = if ($enabled) {
                "Windows FIPS mode: ENABLED (CMVP #4515 validated)"
            } else {
                "Windows FIPS mode: DISABLED"
            }
        }
    }
    catch {
        # Registry key doesn't exist or can't be read
        return @{
            Enabled = $false
            Applicable = $true
            Message = "Windows FIPS mode: DISABLED (policy not configured)"
        }
    }
}

# Cross-platform SecureString to plain text conversion
function ConvertFrom-SecureStringPlain {
    param([System.Security.SecureString]$SecureString)

    if ($IsWindowsPlatform) {
        # Windows: Use Marshal methods
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    else {
        # macOS/Linux: Use NetworkCredential trick
        return [System.Net.NetworkCredential]::new('', $SecureString).Password
    }
}

# CUI Categories per 32 CFR Part 2002
# CUI subcategories (can be combined per 32 CFR Part 2002)
$CUI_SUBCATEGORIES = @{
    "1" = @{ Code = "SP-CTI"; Full = "Controlled Technical Information" }
    "2" = @{ Code = "SP-EXPT"; Full = "Export Controlled" }
    "3" = @{ Code = "SP-PRVCY"; Full = "Privacy" }
    "4" = @{ Code = "SP-PROPIN"; Full = "Proprietary Business Information" }
}

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - CUI File Encryption Tool" -ForegroundColor Cyan
    Write-Host "  FIPS 140-2 / NIST SP 800-171 Compliant" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check and display FIPS mode status
    $fipsStatus = Test-FIPSMode
    if ($fipsStatus.Applicable) {
        if ($fipsStatus.Enabled) {
            Write-Host $fipsStatus.Message -ForegroundColor Green
        }
        else {
            Write-Host "WARNING: $($fipsStatus.Message)" -ForegroundColor Yellow
            Write-Host "  For full NIST SP 800-171 section 3.13.11 compliance, enable FIPS mode:" -ForegroundColor Yellow
            Write-Host "  secpol.msc -> Local Policies -> Security Options ->" -ForegroundColor Gray
            Write-Host "  'System cryptography: Use FIPS compliant algorithms...'" -ForegroundColor Gray
            Write-Host ""
        }
    }
}

function Get-CUICategory {
    Write-Host "Select CUI Subcategories (can select multiple per 32 CFR Part 2002):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [0] CUI (basic - no subcategory)" -ForegroundColor White
    foreach ($key in ($CUI_SUBCATEGORIES.Keys | Sort-Object)) {
        Write-Host "  [$key] $($CUI_SUBCATEGORIES[$key].Code) - $($CUI_SUBCATEGORIES[$key].Full)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Enter selection(s) separated by commas (e.g., '1,2' for CTI+EXPT)" -ForegroundColor Gray
    Write-Host "Or press Enter for basic CUI" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "Selection"

    # Default to basic CUI if empty or 0
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq "0") {
        return @{
            Short = "CUI"
            Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)"
        }
    }

    # Parse comma-separated selections
    $selections = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $CUI_SUBCATEGORIES.ContainsKey($_) } | Sort-Object -Unique

    if ($selections.Count -eq 0) {
        Write-Host "Invalid selection, defaulting to basic CUI" -ForegroundColor Yellow
        return @{
            Short = "CUI"
            Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)"
        }
    }

    # Build the combined marking (e.g., CUI//SP-CTI//SP-EXPT)
    $codes = $selections | ForEach-Object { $CUI_SUBCATEGORIES[$_].Code }
    $shortMarking = "CUI//" + ($codes -join "//")

    $fullNames = $selections | ForEach-Object { $CUI_SUBCATEGORIES[$_].Full }
    $fullMarking = "$shortMarking (" + ($fullNames -join ", ") + ")"

    return @{
        Short = $shortMarking
        Full = $fullMarking
    }
}

# Word list for passphrase generation (EFF-style short words, easy to communicate)
$PASSPHRASE_WORDS = @(
    "apple", "beach", "brave", "bring", "chair", "chief", "class", "cloud",
    "dance", "draft", "dream", "drink", "earth", "elder", "empty", "equal",
    "faint", "faith", "feast", "field", "flame", "flash", "float", "floor",
    "fruit", "giant", "glass", "globe", "grace", "grain", "grape", "grass",
    "green", "grove", "guide", "happy", "heart", "heavy", "horse", "house",
    "human", "image", "inner", "juice", "knife", "lemon", "level", "light",
    "liver", "lodge", "lunar", "magic", "maple", "march", "medal", "metal",
    "model", "money", "month", "motor", "mouse", "music", "noble", "north",
    "novel", "ocean", "olive", "onion", "orbit", "other", "outer", "paint",
    "panel", "paper", "peace", "pearl", "phone", "piano", "pilot", "pixel",
    "plain", "plant", "plate", "plaza", "plum", "point", "polar", "power",
    "pride", "prime", "print", "prize", "proof", "proud", "queen", "quick",
    "quiet", "radio", "rapid", "raven", "reach", "realm", "rider", "river",
    "robin", "robot", "rocky", "round", "royal", "salad", "scale", "scene",
    "scout", "seven", "shade", "shape", "sharp", "sheep", "shell", "shift",
    "shine", "shore", "shown", "sight", "silky", "silver", "simple", "skill"
)

function New-Passphrase {
    param([int]$WordCount = 4)

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $words = @()

    for ($i = 0; $i -lt $WordCount; $i++) {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $index = [Math]::Abs([BitConverter]::ToInt32($bytes, 0)) % $PASSPHRASE_WORDS.Count
        $words += $PASSPHRASE_WORDS[$index]
    }

    $rng.Dispose()
    return ($words -join "-")
}

function Get-SecurePassword {
    param([int]$MaxAttempts = 3)

    Write-Host "Password Options:" -ForegroundColor Yellow
    Write-Host "  - Enter your own password (minimum $MIN_PASSWORD_LENGTH characters)" -ForegroundColor Gray
    Write-Host "  - Press Enter for auto-generated passphrase (recommended)" -ForegroundColor Gray
    Write-Host "  - Will be transmitted out-of-band (phone, SMS, in-person)" -ForegroundColor Gray
    Write-Host ""

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host ""
            Write-Host "Attempt $attempt of $MaxAttempts" -ForegroundColor Yellow
        }

        Write-Host "(Characters will not appear as you type, or press Enter for auto-generate)" -ForegroundColor Gray
        $password = Read-Host "Enter encryption password" -AsSecureString

        # Convert to plain text (cross-platform)
        $plain1 = ConvertFrom-SecureStringPlain -SecureString $password

        # Check if user wants auto-generated passphrase
        if ([string]::IsNullOrEmpty($plain1)) {
            $passphrase = New-Passphrase -WordCount 4
            Write-Host ""
            Write-Host "Generated passphrase:" -ForegroundColor Green
            Write-Host "  $passphrase" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "IMPORTANT: Save this passphrase now - you will share it separately!" -ForegroundColor Yellow
            Write-Host ""

            $confirm = Read-Host "Press Enter to accept, or type 'new' for a different passphrase"
            while ($confirm -eq "new") {
                $passphrase = New-Passphrase -WordCount 4
                Write-Host ""
                Write-Host "Generated passphrase:" -ForegroundColor Green
                Write-Host "  $passphrase" -ForegroundColor Cyan
                Write-Host ""
                $confirm = Read-Host "Press Enter to accept, or type 'new' for a different passphrase"
            }

            return $passphrase
        }

        Write-Host "(Characters will not appear as you type)" -ForegroundColor Gray
        $confirm = Read-Host "Confirm password" -AsSecureString
        $plain2 = ConvertFrom-SecureStringPlain -SecureString $confirm

        if ($plain1 -ne $plain2) {
            Write-Host "ERROR: Passwords do not match!" -ForegroundColor Red
            if ($attempt -lt $MaxAttempts) {
                Write-Host "Please try again." -ForegroundColor Yellow
            }
            continue
        }

        if ($plain1.Length -lt $MIN_PASSWORD_LENGTH) {
            Write-Host "ERROR: Password must be at least $MIN_PASSWORD_LENGTH characters!" -ForegroundColor Red
            if ($attempt -lt $MaxAttempts) {
                Write-Host "Please try again." -ForegroundColor Yellow
            }
            continue
        }

        # Password accepted
        return $plain1
    }

    Write-Host ""
    Write-Host "Maximum password attempts reached. Exiting." -ForegroundColor Red
    return $null
}

function Encrypt-File {
    param(
        [string]$InputPath,
        [string]$Password
    )

    try {
        # Read input file
        $plainBytes = [System.IO.File]::ReadAllBytes($InputPath)

        # Generate random salt and IV
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $salt = New-Object byte[] $SALT_SIZE
        $iv = New-Object byte[] $IV_SIZE
        $rng.GetBytes($salt)
        $rng.GetBytes($iv)

        # Derive key using PBKDF2
        $keyDeriver = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Password,
            $salt,
            $ITERATIONS,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256
        )
        $key = $keyDeriver.GetBytes($KEY_SIZE)

        # Create AES encryptor
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv

        # Encrypt
        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

        # Combine: Salt + IV + Ciphertext
        $outputBytes = New-Object byte[] ($SALT_SIZE + $IV_SIZE + $cipherBytes.Length)
        [Array]::Copy($salt, 0, $outputBytes, 0, $SALT_SIZE)
        [Array]::Copy($iv, 0, $outputBytes, $SALT_SIZE, $IV_SIZE)
        [Array]::Copy($cipherBytes, 0, $outputBytes, $SALT_SIZE + $IV_SIZE, $cipherBytes.Length)

        # Write output file
        $outputPath = "$InputPath.Locked"
        [System.IO.File]::WriteAllBytes($outputPath, $outputBytes)

        # Cleanup
        $aes.Dispose()
        $keyDeriver.Dispose()
        $rng.Dispose()

        return $outputPath
    }
    catch {
        Write-Host "ERROR encrypting $InputPath : $_" -ForegroundColor Red
        return $null
    }
}

function Get-FilesToEncrypt {
    param([string[]]$Paths)

    $files = @()

    foreach ($p in $Paths) {
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($p)) {
            $p = Join-Path (Get-Location) $p
        }

        if (Test-Path $p -PathType Container) {
            # It's a folder - get all files recursively
            $folderFiles = Get-ChildItem -Path $p -File -Recurse |
                           Where-Object { $_.Extension -ne ".Locked" -and $_.Name -ne "Decrypt_Instructions.html" }
            $files += $folderFiles.FullName
        }
        elseif (Test-Path $p -PathType Leaf) {
            # It's a file - get full absolute path
            if ($p -notlike "*.Locked" -and (Split-Path $p -Leaf) -ne "Decrypt_Instructions.html") {
                $files += [System.IO.Path]::GetFullPath($p)
            }
        }
        else {
            Write-Host "WARNING: Path not found: $p" -ForegroundColor Yellow
        }
    }

    return $files
}

function Generate-HtmlInstructions {
    param(
        [string]$OutputDir,
        [string[]]$EncryptedFiles,
        [hashtable]$CUICategory = @{ Short = "CUI"; Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)" }
    )

    # Build file list HTML
    $fileListHtml = ($EncryptedFiles | ForEach-Object { "                <li>$(Split-Path $_ -Leaf)</li>" }) -join "`n"

    # HTML-encode the one-liner for safe display
    $oneLineHtml = $DECRYPTION_ONELINER -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Decrypt Instructions</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: Segoe UI, -apple-system, Arial, sans-serif; line-height: 1.5; max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
        .banner { background: #2196F3; color: white; padding: 12px 20px; text-align: center; font-weight: bold; margin-bottom: 20px; border-radius: 4px; }
        .card { background: white; border-radius: 8px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a1a1a; font-size: 24px; margin-bottom: 8px; }
        h2 { color: #2196F3; font-size: 18px; margin-bottom: 12px; border-bottom: 2px solid #2196F3; padding-bottom: 4px; }
        .step { display: flex; margin-bottom: 16px; }
        .step-num { background: #2196F3; color: white; width: 32px; height: 32px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: bold; flex-shrink: 0; margin-right: 12px; }
        .step-content { flex: 1; }
        .step-title { font-weight: 600; color: #1a1a1a; }
        .code-box { background: #1e1e1e; color: #d4d4d4; padding: 12px; border-radius: 4px; font-family: Consolas, Monaco, monospace; font-size: 12px; overflow-x: auto; margin: 8px 0; word-break: break-all; cursor: pointer; position: relative; }
        .code-box:hover { background: #2d2d2d; }
        .code-box::after { content: "Click to select all"; position: absolute; top: -20px; right: 0; font-size: 11px; color: #666; font-family: Segoe UI, Arial, sans-serif; }
        .tip { background: #E3F2FD; border-left: 4px solid #2196F3; padding: 12px; margin: 12px 0; border-radius: 0 4px 4px 0; }
        .warning { background: #FFF3E0; border-left: 4px solid #FF9800; padding: 12px; margin: 12px 0; border-radius: 0 4px 4px 0; }
        .files { background: #f9f9f9; padding: 12px; border-radius: 4px; margin: 8px 0; }
        .files li { margin-left: 20px; font-family: Consolas, monospace; }
        .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #ddd; }
        @media (max-width: 600px) { .step { flex-direction: column; } .step-num { margin-bottom: 8px; } }
    </style>
</head>
<body>
    <div class="banner">Decryption Instructions</div>

    <div class="card">
        <h1>How to Decrypt Your Files</h1>
        <p>The attached <code>.Locked</code> files are encrypted. Follow these steps to decrypt them.</p>

        <div class="files">
            <strong>Encrypted files:</strong>
            <ul>
$fileListHtml
            </ul>
        </div>
    </div>

    <div class="card" style="background: #FFFDE7;">
        <h2 style="color: #F57C00; border-color: #F57C00;">Before You Start</h2>

        <p><strong>Why can't I just open the .Locked file?</strong><br>
        It's encrypted for security. You need to decrypt it first using the password I sent you separately.</p>

        <p style="margin-top: 12px;"><strong>Do I need to install anything?</strong><br>
        No. PowerShell is already on your Windows computer. Nothing to download or install.</p>

        <p style="margin-top: 12px;"><strong>Is this command safe to run?</strong><br>
        Yes. It only decrypts the file you select - it doesn't access the internet, install anything, or modify your system.</p>

        <p style="margin-top: 12px;"><strong>How long does this take?</strong><br>
        About 30 seconds once you get the hang of it. First time might take 2-3 minutes.</p>

        <p style="margin-top: 12px;"><strong>What if I'm on a Mac?</strong><br>
        These instructions are for Windows. Contact me and I'll send Mac instructions.</p>
    </div>

    <div class="card">
        <h2>Quick Method (Recommended)</h2>

        <div class="step">
            <div class="step-num">1</div>
            <div class="step-content">
                <div class="step-title">Save the attached files</div>
                <p>Download all <code>.Locked</code> files from the email to a folder on your computer (e.g., Desktop or Downloads).</p>
            </div>
        </div>

        <div class="step">
            <div class="step-num">2</div>
            <div class="step-content">
                <div class="step-title">Open PowerShell</div>
                <p>Press <strong>Win+X</strong> then click <strong>"Windows PowerShell"</strong> or <strong>"Terminal"</strong></p>
            </div>
        </div>

        <div class="step">
            <div class="step-num">3</div>
            <div class="step-content">
                <div class="step-title">Copy and paste this command</div>
                <p>Click the box below to select all, then press Ctrl+C to copy:</p>
                <div class="code-box" onclick="this.focus();document.execCommand('selectAll',false,null);" tabindex="0">$oneLineHtml</div>
            </div>
        </div>

        <div class="step">
            <div class="step-num">4</div>
            <div class="step-content">
                <div class="step-title">Paste into PowerShell and press Enter</div>
                <p>Right-click in PowerShell to paste, then press Enter.</p>
            </div>
        </div>

        <div class="step">
            <div class="step-num">5</div>
            <div class="step-content">
                <div class="step-title">Select your .Locked file</div>
                <p>A file picker will open. Navigate to and select the <code>.Locked</code> file you want to decrypt.</p>
            </div>
        </div>

        <div class="step">
            <div class="step-num">6</div>
            <div class="step-content">
                <div class="step-title">Enter the password</div>
                <p>Type the password you received (characters won't appear - this is normal).</p>
            </div>
        </div>

        <div class="step">
            <div class="step-num">7</div>
            <div class="step-content">
                <div class="step-title">Save the decrypted file</div>
                <p>A save dialog will open with the original filename. Click Save.</p>
            </div>
        </div>

        <div class="tip">
            <strong>Tip:</strong> Repeat steps 4-7 for each <code>.Locked</code> file. Use the same password for all files.
        </div>
    </div>

    <div class="card">
        <h2>Troubleshooting</h2>
        <div class="warning">
            <strong>Nothing happens when I type the password?</strong><br>
            This is normal! PowerShell hides password characters for security. Just type it and press Enter.
        </div>
        <div class="warning">
            <strong>Decryption failed?</strong><br>
            Double-check the password. It's case-sensitive.
        </div>
    </div>

    <div class="footer">
        <p>Files encrypted with SendCUIEmail</p>
        <p style="font-size: 10px; color: #999; margin-top: 8px;">
            Encryption: AES-256-CBC (FIPS 140-2) &bull; Key Derivation: PBKDF2-HMAC-SHA256, 100,000 iterations (NIST SP 800-132)<br>
            CUI handling per 32 CFR Part 2002 &bull; Transmission protection per NIST SP 800-171
        </p>
    </div>

    <script>
        // Auto-select code on click
        document.querySelectorAll('.code-box').forEach(box => {
            box.addEventListener('click', function() {
                const range = document.createRange();
                range.selectNodeContents(this);
                const sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
            });
        });
    </script>
</body>
</html>
"@

    $htmlPath = Join-Path $OutputDir "Decrypt_Instructions.html"
    [System.IO.File]::WriteAllText($htmlPath, $html)

    return $htmlPath
}

function Generate-OutlookEmail {
    param(
        [string]$OutputDir,
        [string[]]$EncryptedFiles,
        [string]$ReadmePath,
        [hashtable]$CUICategory
    )

    # Check platform - Outlook COM only available on Windows
    if (-not $IsWindowsPlatform) {
        Write-Host "  NOTE: Outlook .msg generation requires Windows" -ForegroundColor Yellow
        Write-Host "        (Files are ready to attach manually)" -ForegroundColor Gray
        return $null
    }

    # Check if Outlook is available
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    }
    catch {
        Write-Host "  NOTE: Outlook not available - skipping .msg generation" -ForegroundColor Yellow
        Write-Host "        (Files are ready to attach manually)" -ForegroundColor Gray
        return $null
    }

    try {
        # Create new mail item (draft with no recipients - user must add and review)
        $mail = $outlook.CreateItem(0)  # 0 = olMailItem

        # NOTE: $mail.To is intentionally NOT set
        # This creates a draft that requires the user to:
        # 1. Add recipients manually
        # 2. Review the email contents
        # 3. Click Send
        # This is a safety feature to prevent accidental transmission.

        # Build file list for body
        $fileListText = ($EncryptedFiles | ForEach-Object {
            "  - $(Split-Path $_ -Leaf)"
        }) -join "`r`n"

        # Build optional organization sections
        $orgHandling = ""
        if (-not [string]::IsNullOrEmpty($ORG_HANDLING_INSTRUCTIONS)) {
            $orgHandling = "`r`n$ORG_HANDLING_INSTRUCTIONS"
        }

        $orgSupport = ""
        if (-not [string]::IsNullOrEmpty($ORG_SUPPORT_CONTACT)) {
            $orgSupport = "`r`nQUESTIONS: $ORG_SUPPORT_CONTACT`r`n"
        }

        # CUI-compliant subject line
        $mail.Subject = "$($CUICategory.Short) - Encrypted Files - See Decrypt_Instructions.html"

        # CUI-compliant body with sender instructions and banner markings
        $mail.Body = @"
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

$($CUICategory.Full)
================================================================================

This email contains Controlled Unclassified Information (CUI) that requires
safeguarding per 32 CFR Part 2002.

DIGITAL SIGNATURE REQUEST:
If you have a PIV/CAC card or other email signing capability, please reply to
this email with a digitally signed message to confirm receipt. This helps
establish trust and supports compliance verification.

ENCRYPTED FILES ATTACHED:
$fileListText
  - Decrypt_Instructions.html (Decryption Instructions)

DECRYPTION:
The attached files are encrypted using AES-256 (FIPS 140-2 compliant).
Open Decrypt_Instructions.html for step-by-step instructions.
Password will be provided separately.

IF HTML IS INACCESSIBLE - use these steps in Windows PowerShell:
  1. Save the .Locked file(s) to your computer
  2. Run this command (opens file picker dialogs):

$DECRYPTION_ONELINER

HANDLING REQUIREMENTS:
- This information is CUI and must be protected accordingly
- Do not forward without authorization
- Store on approved systems only
- Destroy when no longer needed per retention requirements$orgHandling
$orgSupport
================================================================================
$($CUICategory.Full)
"@

        # Attach all encrypted files
        foreach ($file in $EncryptedFiles) {
            $mail.Attachments.Add($file) | Out-Null
        }

        # Attach HTML instructions
        $mail.Attachments.Add($ReadmePath) | Out-Null

        # Save as .msg file
        $msgPath = Join-Path $OutputDir "CUI_Email_$(Get-Date -Format 'yyyyMMdd_HHmmss').msg"
        $mail.SaveAs($msgPath, 3)  # 3 = olMSG format

        # Cleanup COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null

        return $msgPath
    }
    catch {
        Write-Host "  WARNING: Failed to create .msg file: $_" -ForegroundColor Yellow
        if ($mail) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null }
        if ($outlook) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null }
        return $null
    }
}

function Generate-PasswordEmail {
    param(
        [string]$OutputDir,
        [string]$Password,
        [hashtable]$CUICategory
    )

    # Check platform - Outlook COM only available on Windows
    if (-not $IsWindowsPlatform) {
        return $null
    }

    # Check if Outlook is available
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    }
    catch {
        return $null
    }

    try {
        # Create new mail item (draft with no recipients - user must add and review)
        $mail = $outlook.CreateItem(0)  # 0 = olMailItem

        # NOTE: $mail.To is intentionally NOT set
        # This creates a draft that requires the user to:
        # 1. Add recipients manually
        # 2. Review the email contents
        # 3. Click Send
        # This is a safety feature to prevent accidental transmission.

        # Subject line - intentionally vague for security
        $mail.Subject = "RE: Encrypted Files - Additional Information"

        # Build optional organization support section
        $pwdOrgSupport = ""
        if (-not [string]::IsNullOrEmpty($ORG_SUPPORT_CONTACT)) {
            $pwdOrgSupport = "`r`nQUESTIONS: $ORG_SUPPORT_CONTACT`r`n"
        }

        # Try to set S/MIME encryption flag by default
        # PR_SECURITY_FLAGS: 1 = Encrypt, 2 = Sign, 3 = Both
        $encryptionSet = $false
        try {
            $PR_SECURITY_FLAGS = "http://schemas.microsoft.com/mapi/proptag/0x6E010003"
            $mail.PropertyAccessor.SetProperty($PR_SECURITY_FLAGS, 1)  # 1 = Encrypt
            $encryptionSet = $true
        }
        catch {
            # If setting encryption fails (e.g., no certificate), continue without it
            $encryptionSet = $false
        }

        # Build Option B text based on whether encryption was pre-set
        if ($encryptionSet) {
            $optionBText = @"
OPTION B: S/MIME ENCRYPT THIS EMAIL (If recipient has PIV/CAC)
   [ENCRYPTION PRE-ENABLED] This email is configured to encrypt automatically.
   - Enter recipient's email in "To:" field
   - Click "Sign" (proves it came from you)
   - Verify the lock icon appears (encryption active)
   - If encryption fails, you need the recipient's S/MIME certificate
   - Then send this email
"@
        }
        else {
            $optionBText = @"
OPTION B: S/MIME ENCRYPT THIS EMAIL (If recipient has PIV/CAC)
   [ENCRYPTION NOT PRE-SET] You must manually enable encryption.
   - Enter recipient's email in "To:" field
   - Click "Sign" (proves it came from you)
   - Click "Encrypt" (requires recipient's S/MIME certificate)
   - Then send this email
"@
        }

        # Body with password and security warning
        $mail.Body = @"
********************************************************************************
*                    SENDER INSTRUCTIONS - DELETE BEFORE SENDING               *
********************************************************************************

CHOOSE ONE DELIVERY METHOD:

OPTION A: DO NOT SEND THIS EMAIL (Recommended)
   - Call the recipient and read them the password below
   - Or send via SMS text message
   - Or deliver in person
   - Then DELETE this .msg file

$optionBText

OPTION C: UNENCRYPTED EMAIL - NOT COMPLIANT
   Sending this email unencrypted violates NIST SP 800-63B out-of-band
   requirements, even if sent separately from the encrypted files.

DELETE THIS INSTRUCTION SECTION BEFORE SENDING as acknowledgement that you
understand the compliance requirements.

********************************************************************************

DECRYPTION COMMAND (paste into PowerShell):

$DECRYPTION_ONELINER

================================================================================

DECRYPTION PASSWORD:

    $Password

================================================================================

AFTER DELIVERY:
- Delete this email/file (contains plaintext password)
- Confirm recipient successfully decrypted the files
- Document password transmission per your security procedures
$pwdOrgSupport
================================================================================
"@

        # No attachments for password email

        # Save as .msg file
        $msgPath = Join-Path $OutputDir "Password_Email_$(Get-Date -Format 'yyyyMMdd_HHmmss').msg"
        $mail.SaveAs($msgPath, 3)  # 3 = olMSG format

        # Cleanup COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null

        return $msgPath
    }
    catch {
        if ($mail) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null }
        if ($outlook) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null }
        return $null
    }
}

# Main execution
Write-Banner

# If no files provided, show file picker dialog
if (-not $Path -or $Path.Count -eq 0) {
    Write-Host "No files specified. Opening file picker..." -ForegroundColor Yellow
    Write-Host ""

    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Select files to encrypt"
    $picker.Filter = "All files (*.*)|*.*"
    $picker.Multiselect = $true
    $picker.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($picker.ShowDialog() -eq 'OK') {
        $Path = $picker.FileNames
        Write-Host "Selected $($Path.Count) file(s)" -ForegroundColor Green
    } else {
        Write-Host "No files selected. Exiting." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# Collect files to encrypt
Write-Host "Scanning for files..." -ForegroundColor Gray
$files = Get-FilesToEncrypt -Paths $Path

if ($files.Count -eq 0) {
    Write-Host "ERROR: No files found to encrypt!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($files.Count) file(s) to encrypt:" -ForegroundColor Green
foreach ($f in $files) {
    Write-Host "  - $(Split-Path $f -Leaf)" -ForegroundColor Gray
}
Write-Host ""

# Get CUI category
$cuiCategory = Get-CUICategory
Write-Host ""
Write-Host "Selected: $($cuiCategory.Full)" -ForegroundColor Green
Write-Host ""

# Get password
$password = Get-SecurePassword
if ($null -eq $password) {
    exit 1
}
Write-Host ""

# Determine and display output location upfront
$outputDir = Split-Path $files[0] -Parent
if ([string]::IsNullOrEmpty($outputDir)) {
    $outputDir = Get-Location
}
Write-Host "Output folder:" -ForegroundColor Yellow
Write-Host "  $outputDir" -ForegroundColor White
Write-Host ""

# Encrypt each file
$encryptedFiles = @()

Write-Host "Encrypting files (AES-256-CBC, FIPS 140-2)..." -ForegroundColor Cyan
foreach ($file in $files) {
    Write-Host "  Encrypting: $(Split-Path $file -Leaf)..." -NoNewline
    $result = Encrypt-File -InputPath $file -Password $password
    if ($result) {
        Write-Host " Done" -ForegroundColor Green
        $encryptedFiles += $result
        if ([string]::IsNullOrEmpty($outputDir)) {
            $outputDir = Split-Path $result -Parent
            if ([string]::IsNullOrEmpty($outputDir)) {
                $outputDir = Get-Location
            }
        }
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
    }
}

# Generate HTML instructions and email
if ($encryptedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Generating Decrypt_Instructions.html..." -NoNewline
    $readmePath = Generate-HtmlInstructions -OutputDir $outputDir -EncryptedFiles $encryptedFiles -CUICategory $cuiCategory
    Write-Host " Done" -ForegroundColor Green

    Write-Host "Generating Outlook emails (.msg)..." -NoNewline
    $msgPath = Generate-OutlookEmail -OutputDir $outputDir -EncryptedFiles $encryptedFiles -ReadmePath $readmePath -CUICategory $cuiCategory
    $pwdMsgPath = Generate-PasswordEmail -OutputDir $outputDir -Password $password -CUICategory $cuiCategory
    if ($msgPath) {
        Write-Host " Done" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  Encryption Complete!" -ForegroundColor Green
    Write-Host "  $($cuiCategory.Short)" -ForegroundColor Yellow

    # Show FIPS status in summary
    $fipsStatus = Test-FIPSMode
    if ($fipsStatus.Applicable) {
        if ($fipsStatus.Enabled) {
            Write-Host "  FIPS Mode: ENABLED" -ForegroundColor Green
        }
        else {
            Write-Host "  FIPS Mode: DISABLED (see warning above)" -ForegroundColor Yellow
        }
    }

    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output folder:" -ForegroundColor Yellow
    Write-Host "  $outputDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Files ready to send:" -ForegroundColor Cyan
    foreach ($ef in $encryptedFiles) {
        Write-Host "  $ef" -ForegroundColor White
    }
    Write-Host "  $(Join-Path $outputDir 'Decrypt_Instructions.html')" -ForegroundColor White
    if ($msgPath) {
        Write-Host ""
        Write-Host "Email drafts created:" -ForegroundColor Cyan
        Write-Host "  1. $msgPath" -ForegroundColor White
        Write-Host "     (Encrypted files + HTML instructions)" -ForegroundColor Gray
        if ($pwdMsgPath) {
            Write-Host "  2. $pwdMsgPath" -ForegroundColor White
            Write-Host "     (Password only - SEND SEPARATELY or use alternate channel)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "PASSWORD TRANSMISSION (per NIST SP 800-63B):" -ForegroundColor Yellow
    Write-Host "  [COMPLIANT] Phone call, SMS, or in-person" -ForegroundColor Green
    Write-Host "  [COMPLIANT] S/MIME encrypted email (if recipient has PIV/CAC)" -ForegroundColor Green
    Write-Host "  [NOT COMPLIANT] Unencrypted email - even if separate" -ForegroundColor Red
    Write-Host ""
    Write-Host "OTHER REMINDERS:" -ForegroundColor Yellow
    Write-Host "  - Verify recipient is authorized for CUI" -ForegroundColor Yellow
    Write-Host "  - Document transmission per your retention policy" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "CLEANUP (after sending):" -ForegroundColor Yellow
    Write-Host "  - Delete .msg files from output folder" -ForegroundColor Yellow
    Write-Host "  - Password_Email contains plaintext password" -ForegroundColor Red
    if ($IsWindowsPlatform) {
        Write-Host ""
        Write-Host "TIP: Open output folder:" -ForegroundColor Cyan
        Write-Host "  explorer.exe `"$outputDir`"" -ForegroundColor Gray
    }
}
else {
    Write-Host ""
    Write-Host "ERROR: No files were encrypted successfully." -ForegroundColor Red
    exit 1
}
