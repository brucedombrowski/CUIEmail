#Requires -Version 5.1
<#
.SYNOPSIS
    Decrypts .Locked files created by SendCUIEmail.

.DESCRIPTION
    Decrypts files encrypted with Encrypt.ps1. Version-2 files are authenticated (HMAC-SHA256
    verified before decryption). Version-1 legacy files are decrypted with a warning.
    The format is defined in Crypto.psm1.

    Cross-Platform:
    - Works on Windows PowerShell 5.1+ and PowerShell Core 7+ (macOS/Linux)

.PARAMETER Path
    .Locked files to decrypt. Accepts multiple paths.

.EXAMPLE
    .\Decrypt.ps1 "Document.pdf.Locked"
    .\Decrypt.ps1 "File1.pdf.Locked" "File2.docx.Locked"
#>

param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Path
)

# Crypto.psm1 is the single source of truth for the .Locked format (v2 authenticated, v1 legacy)
Import-Module (Join-Path $PSScriptRoot 'Crypto.psm1') -Force

# Platform detection
$IsWindowsPlatform = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows

# Cross-platform SecureString to plain text conversion
function ConvertFrom-SecureStringPlain {
    param([System.Security.SecureString]$SecureString)

    if ($IsWindowsPlatform) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    else {
        return [System.Net.NetworkCredential]::new('', $SecureString).Password
    }
}

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - File Decryption Tool" -ForegroundColor Cyan
    Write-Host "  FIPS 140-2 / NIST SP 800-171 Compliant" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-Password {
    param([int]$MaxAttempts = 3)

    Write-Host "(Characters will not appear as you type)" -ForegroundColor Gray
    $password = Read-Host "Enter decryption password" -AsSecureString

    # Convert to plain text (cross-platform)
    $plain = ConvertFrom-SecureStringPlain -SecureString $password

    if ([string]::IsNullOrEmpty($plain)) {
        Write-Host "ERROR: Password cannot be empty!" -ForegroundColor Red
        return $null
    }

    return $plain
}

function Decrypt-File {
    param(
        [string]$InputPath,
        [string]$Password
    )

    try {
        if (-not (Test-Path $InputPath -PathType Leaf)) {
            Write-Host "ERROR: File not found: $InputPath" -ForegroundColor Red
            return $null
        }
        if ($InputPath -notlike "*.Locked") {
            Write-Host "ERROR: File does not have .Locked extension: $InputPath" -ForegroundColor Red
            return $null
        }

        $info = Get-CUIFileInfo -InputPath $InputPath
        if (-not $info.Authenticated) {
            Write-Host ""
            Write-Host "  WARNING: legacy version-1 file, no integrity protection. Ask the sender to re-encrypt." -ForegroundColor Yellow
        }

        $outputPath = $InputPath -replace '\.Locked$', ''
        $force = $false
        if (Test-Path $outputPath) {
            Write-Host "WARNING: Output file already exists: $outputPath" -ForegroundColor Yellow
            $overwrite = Read-Host "Overwrite? (y/N)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                Write-Host "Skipped." -ForegroundColor Yellow
                return $null
            }
            $force = $true
        }

        # Tag is verified before any plaintext is produced (REQ-1.7). Nothing is written on failure.
        return Unprotect-CUIFile -InputPath $InputPath -Password $Password -OutputPath $outputPath -Force:$force -WarningAction SilentlyContinue
    }
    catch [System.Security.Cryptography.CryptographicException] {
        Write-Host "ERROR: Decryption failed - wrong password or the file has been modified" -ForegroundColor Red
        return $null
    }
    catch {
        Write-Host "ERROR decrypting $InputPath : $_" -ForegroundColor Red
        return $null
    }
}

function Get-FilesToDecrypt {
    param([string[]]$Paths)

    $files = @()

    foreach ($p in $Paths) {
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($p)) {
            $p = Join-Path (Get-Location) $p
        }

        if (Test-Path $p -PathType Leaf) {
            if ($p -like "*.Locked") {
                $files += [System.IO.Path]::GetFullPath($p)
            }
            else {
                Write-Host "WARNING: Skipping non-.Locked file: $p" -ForegroundColor Yellow
            }
        }
        elseif (Test-Path $p -PathType Container) {
            # It's a folder - get all .Locked files
            $folderFiles = Get-ChildItem -Path $p -Filter "*.Locked" -File -Recurse
            $files += $folderFiles.FullName
        }
        else {
            Write-Host "WARNING: Path not found: $p" -ForegroundColor Yellow
        }
    }

    return $files
}

# Main execution
Write-Banner

# If no files provided, show file picker dialog
if (-not $Path -or $Path.Count -eq 0) {
    Write-Host "No files specified. Opening file picker..." -ForegroundColor Yellow
    Write-Host ""

    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Select .Locked files to decrypt"
    $picker.Filter = "Locked files (*.Locked)|*.Locked|All files (*.*)|*.*"
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

# Collect files to decrypt
Write-Host "Scanning for .Locked files..." -ForegroundColor Gray
$files = Get-FilesToDecrypt -Paths $Path

if ($files.Count -eq 0) {
    Write-Host "ERROR: No .Locked files found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you're providing .Locked files to decrypt." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($files.Count) file(s) to decrypt:" -ForegroundColor Green
foreach ($f in $files) {
    Write-Host "  - $(Split-Path $f -Leaf)" -ForegroundColor Gray
}
Write-Host ""

# Get password
$password = Get-Password
if ($null -eq $password) {
    exit 1
}
Write-Host ""

# Decrypt each file
$decryptedFiles = @()
$failedFiles = @()

Write-Host "Decrypting files (AES-256-CBC + HMAC-SHA256, FIPS 140-2)..." -ForegroundColor Cyan
foreach ($file in $files) {
    Write-Host "  Decrypting: $(Split-Path $file -Leaf)..." -NoNewline
    $result = Decrypt-File -InputPath $file -Password $password
    if ($result) {
        Write-Host " Done" -ForegroundColor Green
        $decryptedFiles += $result
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        $failedFiles += $file
    }
}

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Decryption Complete" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""

if ($decryptedFiles.Count -gt 0) {
    $decryptDir = Split-Path $decryptedFiles[0] -Parent
    if ([string]::IsNullOrEmpty($decryptDir)) {
        $decryptDir = Get-Location
    }
    Write-Host "Output folder:" -ForegroundColor Yellow
    Write-Host "  $decryptDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Successfully decrypted:" -ForegroundColor Green
    foreach ($df in $decryptedFiles) {
        Write-Host "  $df" -ForegroundColor White
    }
}

if ($failedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed to decrypt:" -ForegroundColor Red
    foreach ($ff in $failedFiles) {
        Write-Host "  $ff" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  - Wrong password" -ForegroundColor Yellow
    Write-Host "  - Corrupted file" -ForegroundColor Yellow
    Write-Host "  - File not encrypted with this tool" -ForegroundColor Yellow
}
