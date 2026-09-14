#Requires -Version 5.1
<#
.SYNOPSIS
    Integration test for SendCUIEmail - non-interactive encryption with HTML instructions generation.

.DESCRIPTION
    Used by test.sh to test the full encryption workflow without interactive prompts.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [Parameter(Mandatory=$true)]
    [string]$FileList  # Comma-separated list of files
)

# Parse comma-separated file list
$Files = $FileList -split ','

$ErrorActionPreference = 'Stop'
$ITERATIONS = 100000

try {
    $encryptedFiles = @()

    foreach ($file in $Files) {
        $filePath = Join-Path $OutputDir $file
        if (-not (Test-Path $filePath)) {
            Write-Host "  Skipping (not found): $file" -ForegroundColor Yellow
            continue
        }

        Write-Host "  Encrypting: $file..." -NoNewline
        try {
            $data = [System.IO.File]::ReadAllBytes($filePath)
            $salt = [byte[]]::new(16)
            $iv = [byte[]]::new(16)
            [Security.Cryptography.RandomNumberGenerator]::Fill($salt)
            [Security.Cryptography.RandomNumberGenerator]::Fill($iv)
            $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $salt, $ITERATIONS, 'SHA256')
            $key = $kdf.GetBytes(32)
            $aes = [Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV = $iv
            $enc = $aes.CreateEncryptor()
            $cipher = $enc.TransformFinalBlock($data, 0, $data.Length)
            $output = [byte[]]::new(32 + $cipher.Length)
            [Array]::Copy($salt, 0, $output, 0, 16)
            [Array]::Copy($iv, 0, $output, 16, 16)
            [Array]::Copy($cipher, 0, $output, 32, $cipher.Length)
            $outputPath = Join-Path $OutputDir "$file.Locked"
            [System.IO.File]::WriteAllBytes($outputPath, $output)
            Write-Host " Done" -ForegroundColor Green
            $encryptedFiles += "$file.Locked"
        }
        catch {
            Write-Host " FAILED: $_" -ForegroundColor Red
        }
    }

    # Generate Decrypt_Instructions.html
    Write-Host ""
    Write-Host "Generating Decrypt_Instructions.html..." -NoNewline

    # Build file list HTML
    $fileListHtml = ($encryptedFiles | ForEach-Object { "                <li>$_</li>" }) -join "`n"

    # Decryption one-liner (same as in Encrypt.ps1)
    $oneLiner = 'Add-Type -AssemblyName System.Windows.Forms;$o=New-Object System.Windows.Forms.OpenFileDialog;$o.Title="Select .Locked file to decrypt";$o.Filter="Locked files (*.Locked)|*.Locked|All files (*.*)|*.*";if($o.ShowDialog()-eq''OK''){$f=$o.FileName;$p=Read-Host "Password" -AsSecureString;$b=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$b[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$b[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($b,32,$b.Length-32);$s=New-Object System.Windows.Forms.SaveFileDialog;$s.Title="Save decrypted file as";$s.FileName=[IO.Path]::GetFileName(($f-replace''\.Locked$'',''''));$s.InitialDirectory=[IO.Path]::GetDirectoryName($f);if($s.ShowDialog()-eq''OK''){[IO.File]::WriteAllBytes($s.FileName,$c);Write-Host "Decrypted: $($s.FileName)" -ForegroundColor Green}}'

    # HTML-encode the one-liner
    $oneLineHtml = $oneLiner -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'

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
    Write-Host " Done" -ForegroundColor Green

    Write-Host ""
    Write-Host "Files created:" -ForegroundColor Cyan
    foreach ($ef in $encryptedFiles) {
        Write-Host "  - $ef" -ForegroundColor White
    }
    Write-Host "  - Decrypt_Instructions.html" -ForegroundColor White
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}
