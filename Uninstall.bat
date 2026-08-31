@echo off
setlocal
title Living Fellows - Standalone Uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-Standalone.ps1" -ProjectRoot "%~dp0" %*
if errorlevel 1 (
    echo.
    echo Uninstall failed. Read the error above and see README.md.
    pause
    exit /b 1
)
echo.
pause
