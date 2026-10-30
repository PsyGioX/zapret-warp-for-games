@echo off
chcp 65001 > nul
title Stop Cloudflare WARP and zapret

fltmc > nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "WARPCLI=C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe"

if exist "%WARPCLI%" "%WARPCLI%" disconnect
call "%~dp0service.bat" remove_services_silent
taskkill /IM "Cloudflare WARP.exe" /F > nul 2>&1

echo Cloudflare WARP has been disconnected and closed.
echo zapret and WinDivert services have been removed.
exit
