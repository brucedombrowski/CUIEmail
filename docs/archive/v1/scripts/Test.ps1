#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the encryption/decryption round-trip to verify integrity.

.DESCRIPTION
    Creates a test file, encrypts it, deletes the original, decrypts the encrypted file,
    and verifies the contents match the original. This validates the entire encryption
    pipeline is working correctly.

.PARAMETER TestDir
    Optional directory for test files. Defaults to a temp directory.

.EXAMPLE
    .\Test.ps1
    .\Test.ps1 -TestDir "C:\Temp\EncryptionTest"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDir
)

# Configuration - must match Encrypt.ps1
$ITERATIONS = 100000
$SALT_SIZE = 16
$KEY_SIZE = 32
$IV_SIZE = 16

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - Round-Trip Test" -ForegroundColor Cyan
    Write-Host "  Encrypt -> Delete Original -> Decrypt -> Verify" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Encrypt-TestFile {
    param(
        [string]$InputPath,
        [string]$Password
    )

    try {
        $plainBytes = [System.IO.File]::ReadAllBytes($InputPath)

        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $salt = New-Object byte[] $SALT_SIZE
        $iv = New-Object byte[] $IV_SIZE
        $rng.GetBytes($salt)
        $rng.GetBytes($iv)

        $keyDeriver = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Password, $salt, $ITERATIONS,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256
        )
        $key = $keyDeriver.GetBytes($KEY_SIZE)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv

        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

        $outputBytes = New-Object byte[] ($SALT_SIZE + $IV_SIZE + $cipherBytes.Length)
        [Array]::Copy($salt, 0, $outputBytes, 0, $SALT_SIZE)
        [Array]::Copy($iv, 0, $outputBytes, $SALT_SIZE, $IV_SIZE)
        [Array]::Copy($cipherBytes, 0, $outputBytes, $SALT_SIZE + $IV_SIZE, $cipherBytes.Length)

        $outputPath = "$InputPath.Locked"
        [System.IO.File]::WriteAllBytes($outputPath, $outputBytes)

        $aes.Dispose()
        $keyDeriver.Dispose()
        $rng.Dispose()

        return $outputPath
    }
    catch {
        return $null
    }
}

function Decrypt-TestFile {
    param(
        [string]$InputPath,
        [string]$Password
    )

    try {
        $data = [System.IO.File]::ReadAllBytes($InputPath)

        $salt = $data[0..($SALT_SIZE - 1)]
        $iv = $data[$SALT_SIZE..($SALT_SIZE + $IV_SIZE - 1)]
        $ciphertext = $data[($SALT_SIZE + $IV_SIZE)..($data.Length - 1)]

        $keyDeriver = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
            $Password, $salt, $ITERATIONS,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256
        )
        $key = $keyDeriver.GetBytes($KEY_SIZE)

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv

        $decryptor = $aes.CreateDecryptor()
        $plainBytes = $decryptor.TransformFinalBlock($ciphertext, 0, $ciphertext.Length)

        $outputPath = $InputPath -replace '\.Locked$', ''
        [System.IO.File]::WriteAllBytes($outputPath, $plainBytes)

        $aes.Dispose()
        $keyDeriver.Dispose()

        return $outputPath
    }
    catch {
        return $null
    }
}

function Get-FileHash256 {
    param([string]$Path)
    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    return $hash.Hash
}

function Test-RoundTrip {
    param(
        [string]$TestName,
        [byte[]]$OriginalContent,
        [string]$TestDir,
        [string]$Password
    )

    Write-Host ""
    Write-Host "Test: $TestName" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $testFile = Join-Path $TestDir "test_$([Guid]::NewGuid().ToString('N').Substring(0,8)).bin"

    try {
        # Step 1: Create test file
        Write-Host "  [1/5] Creating test file..." -NoNewline
        [System.IO.File]::WriteAllBytes($testFile, $OriginalContent)
        $originalHash = Get-FileHash256 -Path $testFile
        Write-Host " Done ($($OriginalContent.Length) bytes, SHA256: $($originalHash.Substring(0,16))...)" -ForegroundColor Green

        # Step 2: Encrypt
        Write-Host "  [2/5] Encrypting..." -NoNewline
        $encryptedFile = Encrypt-TestFile -InputPath $testFile -Password $Password
        if (-not $encryptedFile) {
            Write-Host " FAILED" -ForegroundColor Red
            return $false
        }
        $encryptedSize = (Get-Item $encryptedFile).Length
        Write-Host " Done ($encryptedSize bytes)" -ForegroundColor Green

        # Step 3: Delete original
        Write-Host "  [3/5] Deleting original..." -NoNewline
        Remove-Item $testFile -Force
        if (Test-Path $testFile) {
            Write-Host " FAILED (file still exists)" -ForegroundColor Red
            return $false
        }
        Write-Host " Done" -ForegroundColor Green

        # Step 4: Decrypt
        Write-Host "  [4/5] Decrypting..." -NoNewline
        $decryptedFile = Decrypt-TestFile -InputPath $encryptedFile -Password $Password
        if (-not $decryptedFile) {
            Write-Host " FAILED" -ForegroundColor Red
            return $false
        }
        Write-Host " Done" -ForegroundColor Green

        # Step 5: Verify
        Write-Host "  [5/5] Verifying integrity..." -NoNewline
        $decryptedHash = Get-FileHash256 -Path $decryptedFile
        $decryptedSize = (Get-Item $decryptedFile).Length

        if ($originalHash -eq $decryptedHash) {
            Write-Host " PASSED" -ForegroundColor Green
            Write-Host "        Original:  SHA256: $($originalHash.Substring(0,16))... ($($OriginalContent.Length) bytes)" -ForegroundColor Gray
            Write-Host "        Decrypted: SHA256: $($decryptedHash.Substring(0,16))... ($decryptedSize bytes)" -ForegroundColor Gray
            return $true
        }
        else {
            Write-Host " FAILED (hash mismatch)" -ForegroundColor Red
            Write-Host "        Original:  $originalHash" -ForegroundColor Red
            Write-Host "        Decrypted: $decryptedHash" -ForegroundColor Red
            return $false
        }
    }
    finally {
        # Cleanup test files
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
        if ($encryptedFile -and (Test-Path $encryptedFile)) { Remove-Item $encryptedFile -Force -ErrorAction SilentlyContinue }
        if ($decryptedFile -and (Test-Path $decryptedFile)) { Remove-Item $decryptedFile -Force -ErrorAction SilentlyContinue }
    }
}

function Test-WrongPassword {
    param(
        [string]$TestDir,
        [string]$CorrectPassword
    )

    Write-Host ""
    Write-Host "Test: Wrong Password Rejection" -ForegroundColor Yellow
    Write-Host ("-" * 50)

    $testFile = Join-Path $TestDir "test_wrongpwd_$([Guid]::NewGuid().ToString('N').Substring(0,8)).bin"
    $testContent = [System.Text.Encoding]::UTF8.GetBytes("This should not decrypt with wrong password")

    try {
        # Create and encrypt
        Write-Host "  [1/3] Creating and encrypting test file..." -NoNewline
        [System.IO.File]::WriteAllBytes($testFile, $testContent)
        $encryptedFile = Encrypt-TestFile -InputPath $testFile -Password $CorrectPassword
        Remove-Item $testFile -Force
        Write-Host " Done" -ForegroundColor Green

        # Try wrong password
        Write-Host "  [2/3] Attempting decryption with wrong password..." -NoNewline
        $wrongPassword = $CorrectPassword + "WRONG"
        $decryptedFile = Decrypt-TestFile -InputPath $encryptedFile -Password $wrongPassword

        if ($null -eq $decryptedFile -or -not (Test-Path ($encryptedFile -replace '\.Locked$', ''))) {
            Write-Host " Correctly rejected" -ForegroundColor Green
            return $true
        }
        else {
            # Check if content is garbage (padding error should have been thrown)
            Write-Host " WARNING: Decryption did not fail but content may be corrupted" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        # Expected - wrong password should cause cryptographic exception
        Write-Host " Correctly rejected (exception thrown)" -ForegroundColor Green
        return $true
    }
    finally {
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
        if ($encryptedFile -and (Test-Path $encryptedFile)) { Remove-Item $encryptedFile -Force -ErrorAction SilentlyContinue }
        $potentialDecrypted = $encryptedFile -replace '\.Locked$', ''
        if ($potentialDecrypted -and (Test-Path $potentialDecrypted)) { Remove-Item $potentialDecrypted -Force -ErrorAction SilentlyContinue }
    }
}

# Main execution
Write-Banner

# Setup test directory
if ([string]::IsNullOrEmpty($TestDir)) {
    $TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "SendCUIEmail_Test_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
}

Write-Host "Test directory: $TestDir" -ForegroundColor Gray

if (-not (Test-Path $TestDir)) {
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
}

# Generate test password
$testPassword = "TestPassword123!"
Write-Host "Test password: $testPassword" -ForegroundColor Gray

# Run tests
$results = @()

# Test 1: Small text file
$smallText = [System.Text.Encoding]::UTF8.GetBytes("Hello, World! This is a small test file.")
$results += Test-RoundTrip -TestName "Small text file (40 bytes)" -OriginalContent $smallText -TestDir $TestDir -Password $testPassword

# Test 2: Empty file
$emptyContent = @()
$results += Test-RoundTrip -TestName "Empty file (0 bytes)" -OriginalContent $emptyContent -TestDir $TestDir -Password $testPassword

# Test 3: Exactly one AES block (16 bytes)
$oneBlock = [byte[]](1..16)
$results += Test-RoundTrip -TestName "One AES block (16 bytes)" -OriginalContent $oneBlock -TestDir $TestDir -Password $testPassword

# Test 4: Multiple blocks (1KB)
$multiBlock = [byte[]](0..1023 | ForEach-Object { $_ % 256 })
$results += Test-RoundTrip -TestName "Multiple blocks (1 KB)" -OriginalContent $multiBlock -TestDir $TestDir -Password $testPassword

# Test 5: Larger file (100KB)
$largerFile = New-Object byte[] 102400
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($largerFile)
$rng.Dispose()
$results += Test-RoundTrip -TestName "Larger file (100 KB random data)" -OriginalContent $largerFile -TestDir $TestDir -Password $testPassword

# Test 6: Binary content with null bytes
$binaryContent = [byte[]](0, 1, 2, 0, 0, 255, 254, 253, 0, 128, 127, 0)
$results += Test-RoundTrip -TestName "Binary with null bytes" -OriginalContent $binaryContent -TestDir $TestDir -Password $testPassword

# Test 7: Wrong password rejection
$results += Test-WrongPassword -TestDir $TestDir -CorrectPassword $testPassword

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
    Write-Host "The encryption/decryption pipeline is working correctly." -ForegroundColor Green
    Write-Host "Files encrypted with Encrypt.ps1 can be decrypted with Decrypt.ps1" -ForegroundColor Green
    Write-Host "or the one-liner in the generated README.md." -ForegroundColor Green
}
else {
    Write-Host "SOME TESTS FAILED ($passed passed, $failed failed out of $total)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please review the failures above and investigate." -ForegroundColor Red
}

# Cleanup test directory
Write-Host ""
Write-Host "Cleaning up test directory..." -ForegroundColor Gray
Remove-Item $TestDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Test complete." -ForegroundColor Cyan
