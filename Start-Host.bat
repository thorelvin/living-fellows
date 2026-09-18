@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
python host\pzrl_host.py %*
if errorlevel 1 pause
