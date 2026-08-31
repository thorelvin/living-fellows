@echo off
setlocal
title Living Fellows - Standalone Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-Standalone.ps1" -ProjectRoot "%~dp0" %*
if errorlevel 1 (
    echo.
    echo Installation failed. Read the error above and see README.md.
    pause
    exit /b 1
)
echo.
pause
