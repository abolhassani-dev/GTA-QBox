@echo off
chcp 65001 >nul
title Mars Community 2 - MDT download
:: re-run as Administrator (needed to open the firewall port)
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-mdt.ps1"
echo.
pause
