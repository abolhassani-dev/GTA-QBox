@echo off
chcp 65001 >nul
title Mars Community 2 - SERVER
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start.ps1"
echo.
echo Server stopped.
pause
