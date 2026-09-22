@echo off
setlocal
cd /d "%~dp0"
echo One-click setup: Windhawk Portable, taskbar module, and MemoryCleanerFloat.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-And-Run.ps1"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (
  echo Native taskbar embedding was confirmed.
) else (
  echo Installation failed. TaskbarDiagnostic.txt should now be open.
  echo If no report opened, double-click Run-Diagnostic.cmd.
)
pause
exit /b %result%
