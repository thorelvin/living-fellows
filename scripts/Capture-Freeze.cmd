@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Capture-GameThreads.ps1" %*
if errorlevel 1 (
    echo.
    echo Capture failed. Keep the error text and any evidence folder printed above.
)
pause
