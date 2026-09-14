<#
.SYNOPSIS
  Unlock a CUIEmail .locked file with Windows PowerShell 5.1 or PowerShell 7 (fallback when a browser cannot be used).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Unlock.ps1 -Path "C:\Downloads\CUI - Report.docx.locked"
.NOTES
  Format: docs/FILE-FORMAT.md. Key: PBKDF2-HMAC-SHA256 -> 64 bytes (AES-256 key | HMAC key).
  Integrity: HMAC-SHA256 over every byte before the 32-byte tag. Cipher: AES-256-CBC, PKCS7.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Path,
  [Parameter(Mandatory = $false)][string]$Passphrase,
  [Parameter(Mandatory = $false)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
if (-not $Passphrase) { $Passphrase = Read-Host 'Passphrase' }
$b = [IO.File]::ReadAllBytes((Resolve-Path $Path))
if ($b.Length -lt 78) { throw 'File is too short to be a .locked file.' }
if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'CUIL') { throw 'Not a CUIEmail .locked file (bad magic).' }
if ($b[4] -ne 1) { throw "Unsupported .locked format version $($b[4])." }
if ($b[5] -ne 1) { throw "Unsupported key derivation id $($b[5])." }
$iter = [BitConverter]::ToUInt32([byte[]]($b[9], $b[8], $b[7], $b[6]), 0)
$salt = [byte[]]$b[10..25]
$iv   = [byte[]]$b[26..41]
$hlen = [BitConverter]::ToUInt32([byte[]]($b[45], $b[44], $b[43], $b[42]), 0)
if (46 + $hlen + 32 -gt $b.Length) { throw 'File is damaged or incomplete.' }
$header = [Text.Encoding]::UTF8.GetString($b, 46, $hlen) | ConvertFrom-Json
$ctOff = 46 + $hlen
$ctLen = $b.Length - $ctOff - 32

$kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase.Normalize(), $salt, [int]$iter, [Security.Cryptography.HashAlgorithmName]::SHA256)
$keys = $kdf.GetBytes(64)
$encKey = [byte[]]$keys[0..31]
$macKey = [byte[]]$keys[32..63]

$hmac = [Security.Cryptography.HMACSHA256]::new($macKey)
$tag = $hmac.ComputeHash($b, 0, $b.Length - 32)
$expected = [byte[]]$b[($b.Length - 32)..($b.Length - 1)]
$diff = 0; for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($tag[$i] -bxor $expected[$i]) }
if ($diff -ne 0) { throw 'Wrong passphrase, or the file was altered after it was locked.' }

$aes = [Security.Cryptography.Aes]::Create()
$aes.Mode = [Security.Cryptography.CipherMode]::CBC
$aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
$aes.Key = $encKey
$aes.IV = $iv
$plain = $aes.CreateDecryptor().TransformFinalBlock($b, $ctOff, $ctLen)

if (-not $OutDir) { $OutDir = Split-Path -Parent (Resolve-Path $Path) }
$name = if ($header.name) { [IO.Path]::GetFileName([string]$header.name) } else { [IO.Path]::GetFileNameWithoutExtension($Path) }
$out = Join-Path $OutDir $name
[IO.File]::WriteAllBytes($out, $plain)
Write-Host "Unlocked: $out"
if ($header.banner) { Write-Host "This file is marked: $($header.banner)" }
