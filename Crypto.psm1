#Requires -Version 5.1
<#
.SYNOPSIS
    SendCUIEmail cryptographic core. Single source of truth for the .Locked file format.

.DESCRIPTION
    Implements REQ-2026-001 v1.2. Used by Encrypt.ps1, Decrypt.ps1, Test.ps1 and
    TestIntegration.ps1 so the format exists in exactly one place.

    Format version 2 (authenticated, encrypt-then-MAC):

        offset  size  field
        0       4     magic "SCUI"
        4       1     format version = 0x02
        5       4     PBKDF2 iteration count, unsigned 32-bit big-endian
        9       16    salt
        25      16    AES IV
        41      n     AES-256-CBC ciphertext, PKCS7 padding
        41+n    32    HMAC-SHA256 tag over bytes [0, 41+n)

    Key material: PBKDF2-HMAC-SHA256(password, salt, iterations) -> 64 bytes.
    Bytes 0..31 are the AES key, bytes 32..63 are the HMAC key (REQ-1.3).
    The tag is verified before any decryption occurs (REQ-1.7).

    Format version 1 (legacy, no integrity protection):

        [16-byte salt][16-byte IV][ciphertext], 100,000 iterations.

    Version 1 files are detected by the absence of the magic and can still be
    decrypted. Version 1 files are never produced.

    Compliance:
    - FIPS 197 / NIST SP 800-38A   AES-256-CBC
    - FIPS 198-1                   HMAC-SHA256
    - NIST SP 800-132              PBKDF2-HMAC-SHA256
    - NIST SP 800-90A              System CSPRNG for salt and IV
    - NIST SP 800-38D is used where AES-GCM is available; not on Windows PowerShell 5.1.
#>

Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Constants (REQ-2.3, REQ-2.5, REQ-1.5, REQ-5.2)
# ---------------------------------------------------------------------------
$script:MAGIC              = [byte[]](0x53, 0x43, 0x55, 0x49)   # "SCUI"
$script:FORMAT_VERSION     = [byte]2
$script:DEFAULT_ITERATIONS = 600000     # OWASP 2023 floor for PBKDF2-HMAC-SHA256
$script:LEGACY_ITERATIONS  = 100000     # v1 files
$script:SALT_SIZE          = 16
$script:IV_SIZE            = 16
$script:AES_KEY_SIZE       = 32
$script:MAC_KEY_SIZE       = 32
$script:TAG_SIZE           = 32
$script:HEADER_SIZE        = 4 + 1 + 4 + $script:SALT_SIZE + $script:IV_SIZE   # 41
$script:AES_BLOCK          = 16

function Get-CUICryptoParameters {
    <# Returns the format constants for display and for generating instructions. #>
    [PSCustomObject]@{
        FormatVersion     = $script:FORMAT_VERSION
        Cipher            = 'AES-256-CBC'
        Mac               = 'HMAC-SHA256'
        Kdf               = 'PBKDF2-HMAC-SHA256'
        DefaultIterations = $script:DEFAULT_ITERATIONS
        LegacyIterations  = $script:LEGACY_ITERATIONS
        SaltBytes         = $script:SALT_SIZE
        IvBytes           = $script:IV_SIZE
        TagBytes          = $script:TAG_SIZE
        HeaderBytes       = $script:HEADER_SIZE
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function ConvertTo-PasswordBytes {
    param([Parameter(Mandatory)][string]$Password)
    # Same encoding Rfc2898DeriveBytes(string) uses, so v1 files remain decryptable.
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($Password)
}

function Clear-Bytes {
    param([byte[]]$Bytes)
    if ($null -ne $Bytes) { [Array]::Clear($Bytes, 0, $Bytes.Length) }
}

function Get-DerivedKeys {
    <# PBKDF2 -> @{ Aes = 32 bytes; Mac = 32 bytes }. Caller clears both. #>
    param(
        [Parameter(Mandatory)][byte[]]$PasswordBytes,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Iterations
    )
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $PasswordBytes, $Salt, $Iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $material = $kdf.GetBytes($script:AES_KEY_SIZE + $script:MAC_KEY_SIZE)
        $aesKey = New-Object byte[] $script:AES_KEY_SIZE
        $macKey = New-Object byte[] $script:MAC_KEY_SIZE
        [Buffer]::BlockCopy($material, 0, $aesKey, 0, $script:AES_KEY_SIZE)
        [Buffer]::BlockCopy($material, $script:AES_KEY_SIZE, $macKey, 0, $script:MAC_KEY_SIZE)
        Clear-Bytes $material
        return @{ Aes = $aesKey; Mac = $macKey }
    }
    finally {
        $kdf.Dispose()
    }
}

function Test-FixedTimeEqual {
    <# Constant-time comparison. CryptographicOperations.FixedTimeEquals is not on .NET Framework. #>
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) {
        $diff = $diff -bor ($A[$i] -bxor $B[$i])
    }
    return ($diff -eq 0)
}

function Write-UInt32BE {
    param([byte[]]$Buffer, [int]$Offset, [uint32]$Value)
    $Buffer[$Offset]     = [byte](($Value -shr 24) -band 0xFF)
    $Buffer[$Offset + 1] = [byte](($Value -shr 16) -band 0xFF)
    $Buffer[$Offset + 2] = [byte](($Value -shr 8) -band 0xFF)
    $Buffer[$Offset + 3] = [byte]($Value -band 0xFF)
}

function Read-UInt32BE {
    param([byte[]]$Buffer, [int]$Offset)
    return ([uint32]$Buffer[$Offset] -shl 24) -bor ([uint32]$Buffer[$Offset + 1] -shl 16) -bor
           ([uint32]$Buffer[$Offset + 2] -shl 8) -bor [uint32]$Buffer[$Offset + 3]
}

function Test-HasMagic {
    param([byte[]]$Data)
    if ($Data.Length -lt $script:HEADER_SIZE) { return $false }
    for ($i = 0; $i -lt $script:MAGIC.Length; $i++) {
        if ($Data[$i] -ne $script:MAGIC[$i]) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------
# Public: byte-level API
# ---------------------------------------------------------------------------
function Get-CUIFileInfo {
    <#
    .SYNOPSIS
        Inspect a .Locked file or byte array without a password.
    .OUTPUTS
        PSCustomObject: Version (1 or 2), Iterations, Authenticated (bool), CiphertextBytes
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)][string]$InputPath,
        [Parameter(Mandatory, ParameterSetName = 'Bytes')][byte[]]$Data
    )
    if ($PSCmdlet.ParameterSetName -eq 'Path') { $Data = [System.IO.File]::ReadAllBytes($InputPath) }

    if (Test-HasMagic $Data) {
        $version = $Data[4]
        if ($version -ne $script:FORMAT_VERSION) {
            throw "Unsupported .Locked format version $version (this tool supports 1 and 2)"
        }
        $minSize = $script:HEADER_SIZE + $script:AES_BLOCK + $script:TAG_SIZE
        if ($Data.Length -lt $minSize) { throw "File too small to be a valid version-2 .Locked file" }
        return [PSCustomObject]@{
            Version         = 2
            Iterations      = [int](Read-UInt32BE $Data 5)
            Authenticated   = $true
            CiphertextBytes = $Data.Length - $script:HEADER_SIZE - $script:TAG_SIZE
        }
    }

    $minLegacy = $script:SALT_SIZE + $script:IV_SIZE + $script:AES_BLOCK
    if ($Data.Length -lt $minLegacy) { throw "File too small to be a valid .Locked file" }
    return [PSCustomObject]@{
        Version         = 1
        Iterations      = $script:LEGACY_ITERATIONS
        Authenticated   = $false
        CiphertextBytes = $Data.Length - $script:SALT_SIZE - $script:IV_SIZE
    }
}

function Protect-CUIBytes {
    <#
    .SYNOPSIS
        Encrypt and authenticate a byte array. Returns the version-2 .Locked byte layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Plaintext,
        [Parameter(Mandatory)][string]$Password,
        [ValidateRange(1000, 2147483647)][int]$Iterations = $script:DEFAULT_ITERATIONS
    )

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] $script:SALT_SIZE
    $iv   = New-Object byte[] $script:IV_SIZE
    $rng.GetBytes($salt)                     # REQ-2.4, REQ-3.1
    $rng.GetBytes($iv)                       # REQ-1.4
    $rng.Dispose()

    $pwBytes = ConvertTo-PasswordBytes $Password
    $keys = $null
    $aes = $null
    $hmac = $null
    try {
        $keys = Get-DerivedKeys -PasswordBytes $pwBytes -Salt $salt -Iterations $Iterations

        $aes = [System.Security.Cryptography.Aes]::Create()   # REQ-6.1: platform provider
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $keys.Aes
        $aes.IV = $iv
        $encryptor = $aes.CreateEncryptor()
        $cipher = $encryptor.TransformFinalBlock($Plaintext, 0, $Plaintext.Length)
        $encryptor.Dispose()

        $out = New-Object byte[] ($script:HEADER_SIZE + $cipher.Length + $script:TAG_SIZE)
        [Buffer]::BlockCopy($script:MAGIC, 0, $out, 0, 4)
        $out[4] = $script:FORMAT_VERSION
        Write-UInt32BE $out 5 ([uint32]$Iterations)
        [Buffer]::BlockCopy($salt, 0, $out, 9, $script:SALT_SIZE)
        [Buffer]::BlockCopy($iv, 0, $out, 25, $script:IV_SIZE)
        [Buffer]::BlockCopy($cipher, 0, $out, $script:HEADER_SIZE, $cipher.Length)

        # Encrypt-then-MAC over header + ciphertext (REQ-1.3)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
        $tag = $hmac.ComputeHash($out, 0, $script:HEADER_SIZE + $cipher.Length)
        [Buffer]::BlockCopy($tag, 0, $out, $script:HEADER_SIZE + $cipher.Length, $script:TAG_SIZE)

        return ,$out
    }
    finally {
        # REQ-4.4: password material does not outlive the operation
        Clear-Bytes $pwBytes
        if ($keys) { Clear-Bytes $keys.Aes; Clear-Bytes $keys.Mac }
        if ($aes)  { $aes.Dispose() }
        if ($hmac) { $hmac.Dispose() }
    }
}

function Unprotect-CUIBytes {
    <#
    .SYNOPSIS
        Verify and decrypt a .Locked byte array. Throws on authentication failure.
    .DESCRIPTION
        Version 2: the HMAC tag is verified before any decryption (REQ-1.7).
        Version 1: decrypted with a warning; there is no integrity check available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][string]$Password
    )

    $info = Get-CUIFileInfo -Data $Data
    $pwBytes = ConvertTo-PasswordBytes $Password
    $keys = $null
    $aes = $null
    $hmac = $null
    try {
        if ($info.Version -eq 2) {
            $salt = New-Object byte[] $script:SALT_SIZE
            $iv   = New-Object byte[] $script:IV_SIZE
            [Buffer]::BlockCopy($Data, 9, $salt, 0, $script:SALT_SIZE)
            [Buffer]::BlockCopy($Data, 25, $iv, 0, $script:IV_SIZE)

            $keys = Get-DerivedKeys -PasswordBytes $pwBytes -Salt $salt -Iterations $info.Iterations

            $macLen = $Data.Length - $script:TAG_SIZE
            $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
            $expected = $hmac.ComputeHash($Data, 0, $macLen)
            $actual = New-Object byte[] $script:TAG_SIZE
            [Buffer]::BlockCopy($Data, $macLen, $actual, 0, $script:TAG_SIZE)

            if (-not (Test-FixedTimeEqual $expected $actual)) {
                throw [System.Security.Cryptography.CryptographicException]::new(
                    'Authentication failed: wrong password or the file has been modified')
            }

            $cipherOffset = $script:HEADER_SIZE
            $cipherLen = $macLen - $script:HEADER_SIZE
            $aesKey = $keys.Aes
        }
        else {
            Write-Warning 'Legacy version-1 .Locked file: no integrity protection. Re-encrypt with the current tool.'
            $salt = New-Object byte[] $script:SALT_SIZE
            $iv   = New-Object byte[] $script:IV_SIZE
            [Buffer]::BlockCopy($Data, 0, $salt, 0, $script:SALT_SIZE)
            [Buffer]::BlockCopy($Data, $script:SALT_SIZE, $iv, 0, $script:IV_SIZE)

            $keys = Get-DerivedKeys -PasswordBytes $pwBytes -Salt $salt -Iterations $script:LEGACY_ITERATIONS
            $cipherOffset = $script:SALT_SIZE + $script:IV_SIZE
            $cipherLen = $Data.Length - $cipherOffset
            $aesKey = $keys.Aes
        }

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $aesKey
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        $plain = $decryptor.TransformFinalBlock($Data, $cipherOffset, $cipherLen)
        $decryptor.Dispose()
        return ,$plain
    }
    finally {
        Clear-Bytes $pwBytes
        if ($keys) { Clear-Bytes $keys.Aes; Clear-Bytes $keys.Mac }
        if ($aes)  { $aes.Dispose() }
        if ($hmac) { $hmac.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# Public: file-level API
# ---------------------------------------------------------------------------
function Protect-CUIFile {
    <#
    .SYNOPSIS
        Encrypt a file to <InputPath>.Locked (REQ-5.3, REQ-5.4). Returns the output path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$InputPath,
        [Parameter(Mandatory)][string]$Password,
        [string]$OutputPath,
        [int]$Iterations = $script:DEFAULT_ITERATIONS
    )
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "File not found: $InputPath" }
    if (-not $OutputPath) { $OutputPath = "$InputPath.Locked" }

    $plain = [System.IO.File]::ReadAllBytes($InputPath)
    $locked = Protect-CUIBytes -Plaintext $plain -Password $Password -Iterations $Iterations
    [System.IO.File]::WriteAllBytes($OutputPath, $locked)
    return $OutputPath
}

function Unprotect-CUIFile {
    <#
    .SYNOPSIS
        Verify and decrypt a .Locked file. No output file is written unless verification succeeds (REQ-1.7).
    .PARAMETER Force
        Overwrite an existing output file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$InputPath,
        [Parameter(Mandatory)][string]$Password,
        [string]$OutputPath,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "File not found: $InputPath" }
    if (-not $OutputPath) { $OutputPath = $InputPath -replace '\.Locked$', '' }
    if ($OutputPath -eq $InputPath) { throw "Input does not have the .Locked extension: $InputPath" }
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) { throw "Output file already exists: $OutputPath" }

    $data = [System.IO.File]::ReadAllBytes($InputPath)
    $plain = Unprotect-CUIBytes -Data $data -Password $Password
    [System.IO.File]::WriteAllBytes($OutputPath, $plain)
    return $OutputPath
}

function Get-CUIDecryptOneLiner {
    <#
    .SYNOPSIS
        The paste-and-run PowerShell one-liner for recipients. Decrypts version 2 (verified) and version 1 (legacy) files.
        Generated from the module constants so it cannot drift from the format.
    #>
    $hdr = $script:HEADER_SIZE
    $tag = $script:TAG_SIZE
    $legacyIter = $script:LEGACY_ITERATIONS
    $ver = [int]$script:FORMAT_VERSION

    $oneLiner = 'Add-Type -AssemblyName System.Windows.Forms;$o=New-Object System.Windows.Forms.OpenFileDialog;$o.Title="Select .Locked file to decrypt";$o.Filter="Locked files (*.Locked)|*.Locked|All files (*.*)|*.*";if($o.ShowDialog()-eq''OK''){$f=$o.FileName;$p=Read-Host "Password" -AsSecureString;$b=[IO.File]::ReadAllBytes($f);$w=[Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)));' +
        'if($b.Length -gt ' + $hdr + ' -and [Text.Encoding]::ASCII.GetString($b,0,4) -eq "SCUI" -and $b[4] -eq ' + $ver + '){' +
        '$n=([int]$b[5] -shl 24) -bor ([int]$b[6] -shl 16) -bor ([int]$b[7] -shl 8) -bor [int]$b[8];' +
        '$k=[Security.Cryptography.Rfc2898DeriveBytes]::new($w,[byte[]]$b[9..24],$n,"SHA256").GetBytes(64);' +
        '$m=[Security.Cryptography.HMACSHA256]::new([byte[]]$k[32..63]);$t=$m.ComputeHash($b,0,$b.Length-' + $tag + ');$d=0;for($i=0;$i -lt ' + $tag + ';$i++){$d=$d -bor ($t[$i] -bxor $b[$b.Length-' + $tag + '+$i])};' +
        'if($d -ne 0){throw "Authentication failed: wrong password or file modified"};' +
        '$a=[Security.Cryptography.Aes]::Create();$a.Key=[byte[]]$k[0..31];$a.IV=[byte[]]$b[25..40];$c=$a.CreateDecryptor().TransformFinalBlock($b,' + $hdr + ',$b.Length-' + ($hdr + $tag) + ')}' +
        'else{$k=[Security.Cryptography.Rfc2898DeriveBytes]::new($w,[byte[]]$b[0..15],' + $legacyIter + ',"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=[byte[]]$b[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($b,32,$b.Length-32)};' +
        '$s=New-Object System.Windows.Forms.SaveFileDialog;$s.Title="Save decrypted file as";$s.FileName=[IO.Path]::GetFileName(($f-replace''\.Locked$'',''''));$s.InitialDirectory=[IO.Path]::GetDirectoryName($f);if($s.ShowDialog()-eq''OK''){[IO.File]::WriteAllBytes($s.FileName,$c);Write-Host "Decrypted: $($s.FileName)" -ForegroundColor Green}}'
    return $oneLiner
}

Export-ModuleMember -Function Get-CUICryptoParameters, Get-CUIFileInfo, Protect-CUIBytes, Unprotect-CUIBytes, Protect-CUIFile, Unprotect-CUIFile, Get-CUIDecryptOneLiner
