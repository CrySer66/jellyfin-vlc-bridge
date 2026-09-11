@echo off
setlocal
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Desinstaller-GUI.ps1"
exit /b 0
