@echo off
chcp 65001 >nul
title Mars Community 2 - Update
cd /d "%~dp0"
set "GIT=git"
where git >nul 2>&1
if errorlevel 1 (
  for %%D in (D E F C) do (
    if exist "%%D:\Git\cmd\git.exe" set "GIT=%%D:\Git\cmd\git.exe"
    if exist "%%D:\PortableGit\cmd\git.exe" set "GIT=%%D:\PortableGit\cmd\git.exe"
  )
)
echo Downloading the latest changes from the developer...
"%GIT%" pull
if errorlevel 1 (
  echo.
  echo UPDATE FAILED - send a screenshot of this window to the developer.
) else (
  echo.
  echo Update done. Close the server window if it is open, then run start.bat
)
echo.
pause
