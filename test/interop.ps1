# Verifies fallback/Unlock.ps1 (and the one-liner embedded in the app) against files locked by the JavaScript implementation.
# Run: node test/make-fixtures.mjs; then powershell -File test/interop.ps1  (Windows PowerShell 5.1)  or  pwsh -File test/interop.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fx = Join-Path $root 'test/fixtures/out'
$locked = Join-Path $fx 'CUI - Sample Report.docx.locked'
$pass = (Get-Content (Join-Path $fx 'passphrase.txt') -Raw).Trim()
$outDir = Join-Path $fx ("ps-" + $PSVersionTable.PSVersion.Major)
New-Item -ItemType Directory -Force $outDir | Out-Null

& (Join-Path $root 'fallback/Unlock.ps1') -Path $locked -Passphrase $pass -OutDir $outDir
$got = [IO.File]::ReadAllBytes((Join-Path $outDir 'Sample Report.docx'))
$exp = [IO.File]::ReadAllBytes((Join-Path $fx 'expected.bin'))
if ($got.Length -ne $exp.Length) { throw "Length mismatch $($got.Length) vs $($exp.Length)" }
for ($i = 0; $i -lt $got.Length; $i++) { if ($got[$i] -ne $exp[$i]) { throw "Byte mismatch at $i" } }
Write-Host "PASS: Unlock.ps1 round trip on PowerShell $($PSVersionTable.PSVersion)"

$failed = $false
try { & (Join-Path $root 'fallback/Unlock.ps1') -Path $locked -Passphrase 'wrong-wrong-wrong' -OutDir $outDir | Out-Null } catch { $failed = $true; Write-Host "PASS: wrong passphrase rejected: $($_.Exception.Message)" }
if (-not $failed) { throw 'Wrong passphrase was accepted' }

# One-liner from the app (extracted from dist/CUIEmail.html), fed via Read-Host redirection.
$html = Get-Content (Join-Path $root 'dist/CUIEmail.html') -Raw
$m = [regex]::Match($html, 'const PS_ONELINER = String\.raw`([^`]+)`')
if (-not $m.Success) { throw 'one-liner not found in dist' }
$one = $m.Groups[1].Value
$copy = Join-Path $outDir 'CUI - Sample Report.docx.locked'
Copy-Item $locked $copy -Force
Remove-Item (Join-Path $outDir 'Sample Report.docx') -Force
$script = "function Read-Host { param(`$Prompt) if (`$Prompt -like 'Path*') { '$copy' } else { '$pass' } }`n" + $one
$job = & { Invoke-Expression $script }
$got2 = [IO.File]::ReadAllBytes((Join-Path $outDir 'Sample Report.docx'))
if ($got2.Length -ne $exp.Length) { throw 'one-liner length mismatch' }
for ($i = 0; $i -lt $got2.Length; $i += 97) { if ($got2[$i] -ne $exp[$i]) { throw "one-liner byte mismatch at $i" } }
Write-Host "PASS: one-liner round trip on PowerShell $($PSVersionTable.PSVersion)"
