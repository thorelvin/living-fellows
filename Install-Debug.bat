@echo off
setlocal
title Living Fellows - Standalone Installer (DEBUG MENU ON)
echo ================================================================
echo  Living Fellows - DEBUG install
echo  Enables the in-game Debug tab and manual companion spawn.
echo  Playtest only - do not use this build for public/streamed play.
echo  Uninstall.bat removes it and restores the original launcher.
echo ================================================================
echo.
REM %~dp0 ends with a backslash; a bare "%~dp0" makes the trailing \" an escaped
REM quote, so PowerShell swallows the rest of the line into -ProjectRoot and then
REM throws "Illegal characters in the path". Strip the trailing backslash first.
set "LF_ROOT=%~dp0"
if "%LF_ROOT:~-1%"=="\" set "LF_ROOT=%LF_ROOT:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LF_ROOT%\scripts\Install-Standalone.ps1" -ProjectRoot "%LF_ROOT%" -DebugMenu %*
if errorlevel 1 (
    echo.
    echo Installation failed. Read the error above and see README.md.
    pause
    exit /b 1
)
echo.
pause
