@echo off
chcp 65001 > nul
title Ping and packet loss check
cd /d "%~dp0"

echo Measures latency, jitter and packet loss to any host.
echo Run it while WARP is connected to measure the path through the tunnel.
echo Tip: use the IP of your game server for the most meaningful result.
echo:
set "target="
set /p "target=Target IP or host [Enter = 1.1.1.1]: "
if not defined target set "target=1.1.1.1"
set "count="
set /p "count=Number of probes [Enter = 50]: "
if not defined count set "count=50"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\warp-quality.ps1" -Target "%target%" -Count %count%
echo:
pause
