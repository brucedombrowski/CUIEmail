@echo off
REM SendCUIEmail - Encrypt files for secure transmission
REM Drag files/folders onto this batch file, or run from command line

setlocal EnableDelayedExpansion

REM Check for PowerShell
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell is not available on this system.
    pause
    exit /b 1
)

REM Build argument list for PowerShell
set "ARGS="
:argloop
if "%~1"=="" goto endargs
set "ARGS=!ARGS! "%~1""
shift
goto argloop
:endargs

REM Run PowerShell script (will show file picker if no files provided)
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Encrypt.ps1" !ARGS!

pause
