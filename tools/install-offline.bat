@echo off
chcp 65001 >nul
title Mars Community 2 - Installer (offline)
:: re-run as Administrator (needed to open the firewall port)
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Offline
echo.
pause
