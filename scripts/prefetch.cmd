@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prefetch.ps1" %*
pause
