@echo off
setlocal
title Installation de Jellyfin VLC Bridge
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Installer-GUI.ps1"
if errorlevel 1 (
  echo.
  echo L'installation a rencontre une erreur.
  pause
  exit /b 1
)
exit /b 0
