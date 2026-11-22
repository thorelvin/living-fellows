@echo off
setlocal
title Living Fellows - Standalone Uninstaller
REM %~dp0 ends with a backslash; a bare "%~dp0" makes the trailing \" an escaped
REM quote, so PowerShell swallows the rest of the line into -ProjectRoot and then
REM throws "Illegal characters in the path". Strip the trailing backslash first.
set "LF_ROOT=%~dp0"
if "%LF_ROOT:~-1%"=="\" set "LF_ROOT=%LF_ROOT:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LF_ROOT%\scripts\Uninstall-Standalone.ps1" -ProjectRoot "%LF_ROOT%" %*
if errorlevel 1 (
    echo.
    echo Uninstall failed. Read the error above.
    echo  - Close Project Zomboid completely. Saving can take a minute; check that
    echo    ProjectZomboid64.exe has gone from Task Manager, then run this again.
    echo  - Run Uninstall.bat from a complete extracted download, not from inside a ZIP.
    echo  - If it still fails, include the error above in a bug report. See INSTALL.md.
    pause
    exit /b 1
)
echo.
pause
