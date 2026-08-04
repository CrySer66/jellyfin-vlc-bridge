@echo off
setlocal
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Desinstaller-GUI.ps1"
exit /b 0
