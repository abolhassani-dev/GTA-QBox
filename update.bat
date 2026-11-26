@echo off
chcp 65001 >nul
title Mars Community 2 - Update
cd /d "%~dp0"
echo Downloading the latest changes from the developer...
git pull
if errorlevel 1 (
  echo.
  echo UPDATE FAILED - send a screenshot of this window to the developer.
) else (
  echo.
  echo Update done. Close the server window if it is open, then run start.bat
)
echo.
pause
