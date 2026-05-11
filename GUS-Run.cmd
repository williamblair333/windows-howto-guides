@echo off
REM ============================================================================
REM GUS-Run.cmd -- the "just make it work" launcher.
REM
REM Double-click to install GUS. Or from a prompt:
REM     GUS-Run.cmd
REM     GUS-Run.cmd -Diagnose
REM     GUS-Run.cmd -Repair
REM     GUS-Run.cmd -IncludeOhMyPosh -IncludeNerdFonts
REM     GUS-Run.cmd -Restore
REM
REM Handles automatically:
REM   1. Mark of the Web (MOTW) from OneDrive/download:
REM      Unblock-File runs on every GUS-*.ps1 in this folder first.
REM   2. Execution policy:
REM      Bypass is set for this process only (does not change persistent policy).
REM   3. Path-with-spaces:
REM      Quoted everywhere.
REM ============================================================================

setlocal
cd /d "%~dp0"

REM Step 1: Strip MOTW from all GUS-*.ps1 in this folder.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -Path '.' -Filter 'GUS*.ps1' | Unblock-File"

REM Step 2: Run the orchestrator, forwarding any args to it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\GUS-Invoke.ps1" %*
set "RC=%ERRORLEVEL%"

REM Step 3: If launched by double-click, keep the window open so output is readable.
REM CMDCMDLINE check: when double-clicked, command line ends with this script's
REM name; when run from an existing shell it contains /c or just cmd.exe.
echo %CMDCMDLINE% | findstr /i /c:"%~nx0" >nul
if not errorlevel 1 (
    echo.
    echo Press any key to close...
    pause >nul
)

endlocal & exit /b %RC%
