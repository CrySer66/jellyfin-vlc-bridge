@echo off
setlocal
title Desinstallation de Jellyfin VLC Bridge
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Desinstaller-JellyfinVlcBridge.ps1"
if errorlevel 1 (
  echo.
  echo La desinstallation a rencontre une erreur.
  pause
  exit /b 1
)
echo.
echo Desinstallation terminee.
pause
