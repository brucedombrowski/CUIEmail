#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the SendCUIEmail cryptographic core (Crypto.psm1).

.DESCRIPTION
    Exercises the same module that Encrypt.ps1 and Decrypt.ps1 use, so a regression in the
    shipping code is caught here. Covers REQ-2026-001 v1.2:
      - Round trip: encrypt, delete original, decrypt, compare SHA-256
      - Wrong password is rejected deterministically (REQ-1.7)
      - Tampered ciphertext, header, and tag are rejected (REQ-1.3)
      - No output file is written when verification fails (REQ-1.7)
      - Iteration count is carried in the header (REQ-2.7)
      - Legacy version-1 files still decrypt

.PARAMETER TestDir
    Optional directory for test files. Defaults to a temp directory.

.PARAMETER Iterations
    PBKDF2 iterations for test vectors. Low by default so the suite runs in seconds;
    the format stores the count, so the shipping default is exercised by the one
    round-trip test that omits this parameter.

.EXAMPLE
    .\Test.ps1
    .\Test.ps1 -TestDir "C:\Temp\EncryptionTest"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDir,

    [Parameter(Mandatory=$false)]
    [int]$Iterations = 2000
)

Import-Module (Join-Path $PSScriptRoot 'Crypto.psm1') -Force
$CRYPTO = Get-CUICryptoParameters

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - Crypto Core Test" -ForegroundColor Cyan
    Write-Host "  Format v$($CRYPTO.FormatVersion): $($CRYPTO.Cipher) + $($CRYPTO.Mac), $($CRYPTO.Kdf)" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-FileHash256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function New-TestPath {
    param([string]$Dir, [string]$Prefix)
    return Join-Path $Dir "$Prefix`_$([Guid]::NewGuid().ToString('N').Substring(0,8)).bin"
}

function Write-Result {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  PASS  $Label" -ForegroundColor Green }
    else     { Write-Host "  FAIL  $Label" -ForegroundColor Red }
    if ($Detail) { Write-Host "        $Detail" -ForegroundColor Gray }
    return $Ok
}

# Legacy v1 writer, kept only as a test fixture. Never used by the tool.
function New-LegacyV1File {
    param([string]$Path, [byte[]]$Content, [string]$Password)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $iv = New-Object byte[] 16
    $rng.GetBytes($salt); $rng.GetBytes($iv); $rng.Dispose()
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $salt, $CRYPTO.LegacyIterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $kdf.GetBytes(32); $aes.IV = $iv
    $cipher = $aes.CreateEncryptor().TransformFinalBlock($Content, 0, $Content.Length)
    $out = New-Object byte[] (32 + $cipher.Length)
    [Buffer]::BlockCopy($salt, 0, $out, 0, 16)
    [Buffer]::BlockCopy($iv, 0, $out, 16, 16)
    [Buffer]::BlockCopy($cipher, 0, $out, 32, $cipher.Length)
    [System.IO.File]::WriteAllBytes($Path, $out)
    $aes.Dispose(); $kdf.Dispose()
}

function Test-RoundTrip {
    param([string]$TestName, [byte[]]$OriginalContent, [string]$TestDir, [string]$Password, [int]$Iter)

    Write-Host ""
    Write-Host "Test: $TestName" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $testFile = New-TestPath $TestDir 'test_roundtrip'
    $encryptedFile = $null; $decryptedFile = $null
    try {
        [System.IO.File]::WriteAllBytes($testFile, $OriginalContent)
        $originalHash = Get-FileHash256 -Path $testFile

        $encryptedFile = if ($Iter -gt 0) { Protect-CUIFile -InputPath $testFile -Password $Password -Iterations $Iter }
                         else             { Protect-CUIFile -InputPath $testFile -Password $Password }
        $info = Get-CUIFileInfo -InputPath $encryptedFile
        $expectedSize = $CRYPTO.HeaderBytes + ([math]::Floor($OriginalContent.Length / 16) + 1) * 16 + $CRYPTO.TagBytes
        $ok = Write-Result "Encrypted: v$($info.Version), $($info.Iterations) iterations, $((Get-Item $encryptedFile).Length) bytes" `
            (($info.Version -eq 2) -and ($info.Authenticated) -and ((Get-Item $encryptedFile).Length -eq $expectedSize))

        Remove-Item $testFile -Force
        $decryptedFile = Unprotect-CUIFile -InputPath $encryptedFile -Password $Password
        $decryptedHash = Get-FileHash256 -Path $decryptedFile
        $ok = (Write-Result "Decrypted, SHA-256 matches original" ($originalHash -eq $decryptedHash) "SHA256: $($originalHash.Substring(0,16))... ($($OriginalContent.Length) bytes)") -and $ok
        return $ok
    }
    catch {
        return Write-Result "Exception: $_" $false
    }
    finally {
        foreach ($f in @($testFile, $encryptedFile, $decryptedFile)) {
            if ($f -and (Test-Path $f)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Test-WrongPassword {
    param([string]$TestDir, [string]$CorrectPassword, [int]$Iter, [int]$Attempts = 300)

    Write-Host ""
    Write-Host "Test: Wrong Password Rejection ($Attempts attempts, must reject every one)" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $content = [System.Text.Encoding]::UTF8.GetBytes("This should not decrypt with wrong password")
    $locked = Protect-CUIBytes -Plaintext $content -Password $CorrectPassword -Iterations $Iter
    $rejected = 0
    for ($i = 0; $i -lt $Attempts; $i++) {
        try { $null = Unprotect-CUIBytes -Data $locked -Password "$CorrectPassword-wrong-$i" }
        catch [System.Security.Cryptography.CryptographicException] { $rejected++ }
    }
    $ok = Write-Result "Rejected $rejected / $Attempts (v1 format would pass ~1 in 256 by chance)" ($rejected -eq $Attempts)

    # File API: no output file may exist after a failed verification (REQ-1.7)
    $testFile = New-TestPath $TestDir 'test_wrongpwd'
    [System.IO.File]::WriteAllBytes($testFile, $content)
    $encryptedFile = Protect-CUIFile -InputPath $testFile -Password $CorrectPassword -Iterations $Iter
    Remove-Item $testFile -Force
    $threw = $false
    try { $null = Unprotect-CUIFile -InputPath $encryptedFile -Password "$CorrectPassword-wrong" } catch { $threw = $true }
    $ok = (Write-Result "No output file written on failure" ($threw -and -not (Test-Path $testFile))) -and $ok
    Remove-Item $encryptedFile -Force -ErrorAction SilentlyContinue
    return $ok
}

function Test-Tamper {
    param([string]$Password, [int]$Iter)

    Write-Host ""
    Write-Host "Test: Tamper Detection" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $content = New-Object byte[] 1000
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($content); $rng.Dispose()
    $locked = Protect-CUIBytes -Plaintext $content -Password $Password -Iterations $Iter
    $hdr = $CRYPTO.HeaderBytes

    $cases = [ordered]@{
        'version byte'          = 4
        'iteration count'       = 6
        'salt'                  = 12
        'IV'                    = 30
        'first ciphertext byte' = $hdr
        'last ciphertext byte'  = $locked.Length - $CRYPTO.TagBytes - 1
        'tag'                   = $locked.Length - 1
    }
    $ok = $true
    foreach ($name in $cases.Keys) {
        $t = [byte[]]$locked.Clone()
        $t[$cases[$name]] = $t[$cases[$name]] -bxor 0x01
        $rejected = $false
        try { $null = Unprotect-CUIBytes -Data $t -Password $Password } catch { $rejected = $true }
        $ok = (Write-Result "Flipped one bit in $name (offset $($cases[$name]))" $rejected) -and $ok
    }

    $rejected = $false
    try { $null = Unprotect-CUIBytes -Data ([byte[]]$locked[0..($locked.Length - 2)]) -Password $Password } catch { $rejected = $true }
    $ok = (Write-Result "Truncated by one byte" $rejected) -and $ok

    $rejected = $false
    try { $null = Unprotect-CUIBytes -Data ([byte[]]($locked + [byte]0)) -Password $Password } catch { $rejected = $true }
    $ok = (Write-Result "Extended by one byte" $rejected) -and $ok
    return $ok
}

function Test-HeaderIterations {
    param([string]$Password)

    Write-Host ""
    Write-Host "Test: Iteration Count Carried in Header" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $content = [System.Text.Encoding]::UTF8.GetBytes("iteration count test")
    $ok = $true
    foreach ($n in 1000, 123456, $CRYPTO.DefaultIterations) {
        $locked = Protect-CUIBytes -Plaintext $content -Password $Password -Iterations $n
        $info = Get-CUIFileInfo -Data $locked
        $back = Unprotect-CUIBytes -Data $locked -Password $Password
        $same = ([System.Text.Encoding]::UTF8.GetString($back) -eq "iteration count test")
        $ok = (Write-Result "Iterations=$n read back as $($info.Iterations), decrypts" (($info.Iterations -eq $n) -and $same)) -and $ok
    }
    return $ok
}

function Test-LegacyV1 {
    param([string]$TestDir, [string]$Password)

    Write-Host ""
    Write-Host "Test: Legacy Version-1 File" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $content = [System.Text.Encoding]::UTF8.GetBytes("legacy file written by SendCUIEmail v0.x")
    $legacyFile = (New-TestPath $TestDir 'test_legacy') + '.Locked'
    $decrypted = $null
    try {
        New-LegacyV1File -Path $legacyFile -Content $content -Password $Password
        $info = Get-CUIFileInfo -InputPath $legacyFile
        $ok = Write-Result "Detected as v$($info.Version), authenticated=$($info.Authenticated)" (($info.Version -eq 1) -and -not $info.Authenticated)
        $decrypted = Unprotect-CUIFile -InputPath $legacyFile -Password $Password -WarningAction SilentlyContinue
        $same = ([System.IO.File]::ReadAllText($decrypted) -eq "legacy file written by SendCUIEmail v0.x")
        $ok = (Write-Result "Decrypts with a warning" $same) -and $ok
        return $ok
    }
    catch {
        return Write-Result "Exception: $_" $false
    }
    finally {
        foreach ($f in @($legacyFile, $decrypted)) { if ($f -and (Test-Path $f)) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    }
}

# Main execution
Write-Banner

if ([string]::IsNullOrEmpty($TestDir)) {
    $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "SendCUIEmail_Test_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
}
Write-Host "Test directory: $TestDir" -ForegroundColor Gray
if (-not (Test-Path $TestDir)) { New-Item -ItemType Directory -Path $TestDir -Force | Out-Null }

$testPassword = "TestPassword123!"
Write-Host "Test password: $testPassword" -ForegroundColor Gray
Write-Host "Test iterations: $Iterations (shipping default $($CRYPTO.DefaultIterations))" -ForegroundColor Gray

$results = @()

$results += Test-RoundTrip -TestName "Small text file (40 bytes)" -OriginalContent ([System.Text.Encoding]::UTF8.GetBytes("Hello, World! This is a small test file.")) -TestDir $TestDir -Password $testPassword -Iter $Iterations
$results += Test-RoundTrip -TestName "Empty file (0 bytes)" -OriginalContent (New-Object byte[] 0) -TestDir $TestDir -Password $testPassword -Iter $Iterations
$results += Test-RoundTrip -TestName "One AES block (16 bytes)" -OriginalContent ([byte[]](1..16)) -TestDir $TestDir -Password $testPassword -Iter $Iterations
$results += Test-RoundTrip -TestName "Multiple blocks (1 KB)" -OriginalContent ([byte[]](0..1023 | ForEach-Object { $_ % 256 })) -TestDir $TestDir -Password $testPassword -Iter $Iterations

$largerFile = New-Object byte[] 102400
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($largerFile); $rng.Dispose()
$results += Test-RoundTrip -TestName "Larger file (100 KB random data)" -OriginalContent $largerFile -TestDir $TestDir -Password $testPassword -Iter $Iterations
$results += Test-RoundTrip -TestName "Binary with null bytes" -OriginalContent ([byte[]](0, 1, 2, 0, 0, 255, 254, 253, 0, 128, 127, 0)) -TestDir $TestDir -Password $testPassword -Iter $Iterations
$results += Test-RoundTrip -TestName "Shipping default iterations ($($CRYPTO.DefaultIterations))" -OriginalContent ([System.Text.Encoding]::UTF8.GetBytes("default iteration count")) -TestDir $TestDir -Password $testPassword -Iter 0

$results += Test-WrongPassword -TestDir $TestDir -CorrectPassword $testPassword -Iter $Iterations
$results += Test-Tamper -Password $testPassword -Iter $Iterations
$results += Test-HeaderIterations -Password $testPassword
$results += Test-LegacyV1 -TestDir $TestDir -Password $testPassword

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$passed = ($results | Where-Object { $_ -eq $true }).Count
$failed = ($results | Where-Object { $_ -eq $false }).Count
$total = $results.Count

if ($failed -eq 0) {
    Write-Host "ALL TESTS PASSED ($passed/$total)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files encrypted with Encrypt.ps1 can be decrypted with Decrypt.ps1" -ForegroundColor Green
    Write-Host "or the one-liner in Decrypt_Instructions.html." -ForegroundColor Green
}
else {
    Write-Host "SOME TESTS FAILED ($passed passed, $failed failed out of $total)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Cleaning up test directory..." -ForegroundColor Gray
Remove-Item $TestDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Test complete." -ForegroundColor Cyan
if ($failed -ne 0) { exit 1 }
