@echo off
REM Opens PowerShell in the current folder
REM Recipients can use this to run the decryption one-liner from the README

start powershell -NoExit -Command "Write-Host 'PowerShell ready. Paste the decryption command from README.md' -ForegroundColor Cyan; Write-Host 'Current folder:' (Get-Location) -ForegroundColor Yellow"
