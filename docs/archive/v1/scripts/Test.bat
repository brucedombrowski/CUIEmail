@echo off
REM SendCUIEmail - Run encryption round-trip tests
REM Verifies that encryption and decryption work correctly

echo.
echo Running SendCUIEmail round-trip tests...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Test.ps1"

pause
