@echo off
rem Runs install.ps1 for this session only, bypassing the PowerShell execution policy.
rem Extra arguments are passed through, e.g.  install.bat -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
