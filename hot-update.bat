@echo off
chcp 65001 >nul
title Mars Community 2 - Live update (no restart)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\hotupdate.ps1"
echo.
pause
