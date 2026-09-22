@echo off
setlocal
cd /d "%~dp0"
echo Creating TaskbarDiagnostic.txt...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TaskbarDiagnostic.ps1"
set "result=%errorlevel%"
if not "%result%"=="0" (
  echo.
  echo Diagnostic failed. Please take a screenshot of this window.
  pause
)
exit /b %result%
