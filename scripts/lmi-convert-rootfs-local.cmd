@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lmi-convert-rootfs-local.ps1" %*
exit /b %ERRORLEVEL%
