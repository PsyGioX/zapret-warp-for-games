@echo off
chcp 65001 > nul
title Games via Cloudflare WARP
setlocal EnableExtensions EnableDelayedExpansion

fltmc > nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
set "ROOT=%~dp0"
set "CFG=%ROOT%utils\warp_launcher.cfg"
set "GFFILE=%ROOT%utils\game_filter.enabled"

set "WARPCLI=C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe"
set "WARPAPP=C:\Program Files\Cloudflare\Cloudflare WARP\Cloudflare WARP.exe"

rem Documented Cloudflare WARP (MASQUE) fallback UDP ports. The default port 443 is always captured by every profile.
set "WARP_UDP_PORTS=500,1701,4443,4500,8095,8443"
set "ALL_PORTS=1024-65535"

if not exist "%WARPCLI%" (
    echo ERROR: Cloudflare WARP is not installed.
    echo Run "1 - INSTALL Cloudflare WARP.bat" first.
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if not errorlevel 1 (
    echo ERROR: zapret is already running.
    echo Return to the existing launcher window and press Enter to stop it.
    echo If that window was closed, run "3 - STOP WARP and zapret.bat".
    pause
    exit /b 1
)

rem ---------- remembered choices ----------
set "lastProfile="
set "lastMode=1"
set "lastTcp="
set "lastUdp="
if exist "%CFG%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CFG%") do (
        if /i "%%A"=="profile" set "lastProfile=%%B"
        if /i "%%A"=="mode" set "lastMode=%%B"
        if /i "%%A"=="tcp" set "lastTcp=%%B"
        if /i "%%A"=="udp" set "lastUdp=%%B"
    )
)

rem ---------- profile selection ----------
echo:
echo Select a zapret profile:
set "profileCount=0"
set "lastIdx="
for %%F in ("%~dp0general*.bat") do if exist "%%~fF" (
    set /a profileCount+=1
    set "profile!profileCount!=%%~nxF"
    if /i "%%~nxF"=="!lastProfile!" (
        set "lastIdx=!profileCount!"
        echo   !profileCount!. %%~nxF   ^<-- last used
    ) else (
        echo   !profileCount!. %%~nxF
    )
)

if !profileCount! EQU 0 (
    echo ERROR: No general BAT profiles were found.
    pause
    exit /b 1
)

echo:
set "profileChoice="
if defined lastIdx (
    set /p "profileChoice=Enter profile number [Enter = !lastIdx!]: "
) else (
    set /p "profileChoice=Enter profile number: "
)
if not defined profileChoice set "profileChoice=!lastIdx!"

if not defined profileChoice goto invalid_profile
for /f "delims=0123456789" %%A in ("!profileChoice!") do goto invalid_profile
if !profileChoice! LSS 1 goto invalid_profile
if !profileChoice! GTR !profileCount! goto invalid_profile

set "selectedProfile=!profile%profileChoice%!"

rem ---------- capture mode selection ----------
echo:
echo Select capture mode (which ports zapret/WinDivert intercepts):
echo   1. Low latency   - only WARP tunnel ports (recommended, least overhead)
echo   2. Compatibility - all ports 1024-65535 TCP+UDP (heavier, use if mode 1 fails)
echo   3. Custom ports
echo:
set "modeChoice="
set /p "modeChoice=Mode [Enter = !lastMode!]: "
if not defined modeChoice set "modeChoice=!lastMode!"

set "gfMode=udp"
set "gfTcp=%ALL_PORTS%"
set "gfUdp=%WARP_UDP_PORTS%"

if "!modeChoice!"=="2" (
    set "gfMode=all"
    set "gfTcp=%ALL_PORTS%"
    set "gfUdp=%ALL_PORTS%"
) else if "!modeChoice!"=="3" (
    echo:
    echo Enter ports or ranges separated by commas, for example: 3074,27000-27100
    echo Leave a field empty to skip that protocol.
    set "cTcp="
    set "cUdp="
    set /p "cUdp=UDP ports [Enter = !lastUdp!]: "
    set /p "cTcp=TCP ports [Enter = !lastTcp!]: "
    if not defined cUdp set "cUdp=!lastUdp!"
    if not defined cTcp set "cTcp=!lastTcp!"
    if defined cUdp (
        echo(!cUdp!| findstr /r /x /c:"[0-9][0-9,-]*" > nul || goto invalid_ports
    )
    if defined cTcp (
        echo(!cTcp!| findstr /r /x /c:"[0-9][0-9,-]*" > nul || goto invalid_ports
    )
    set "gfMode=disabled"
    if defined cUdp if defined cTcp set "gfMode=all"
    if defined cUdp if not defined cTcp set "gfMode=udp"
    if not defined cUdp if defined cTcp set "gfMode=tcp"
    if defined cUdp (set "gfUdp=!cUdp!") else set "gfUdp=%ALL_PORTS%"
    if defined cTcp (set "gfTcp=!cTcp!") else set "gfTcp=%ALL_PORTS%"
) else (
    set "modeChoice=1"
)

rem ---------- save choices ----------
if not "!modeChoice!"=="3" (
    set "cTcp=!lastTcp!"
    set "cUdp=!lastUdp!"
)
(
    echo profile=!selectedProfile!
    echo mode=!modeChoice!
    echo tcp=!cTcp!
    echo udp=!cUdp!
)>"%CFG%"

set "compatTried=0"
if "!modeChoice!"=="2" set "compatTried=1"

:launch
(
    echo mode=!gfMode!
    echo tcp=!gfTcp!
    echo udp=!gfUdp!
)>"%GFFILE%"

echo:
echo Starting "!selectedProfile!" - capture mode: !gfMode! ^(TCP !gfTcp! / UDP !gfUdp!^)
call "%~dp0!selectedProfile!"
timeout /t 3 /nobreak > nul

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if errorlevel 1 (
    echo ERROR: winws.exe did not start. Check antivirus and WinDivert, then try another profile.
    pause
    exit /b 1
)

echo Raising winws.exe priority to reduce packet queuing delay...
powershell -NoProfile -Command "Get-Process winws -ErrorAction SilentlyContinue | ForEach-Object { try { $_.PriorityClass = 'High' } catch {} }"

echo Selecting the MASQUE tunnel protocol...
"%WARPCLI%" tunnel protocol set MASQUE

if exist "%WARPAPP%" start "" "%WARPAPP%"

echo Connecting Cloudflare WARP...
"%WARPCLI%" connect

set "connected=0"
echo Waiting for the tunnel (up to 30 s)...
for /l %%i in (1,1,30) do if "!connected!"=="0" (
    "%WARPCLI%" status 2>nul | findstr /C:"Status update: Connected" > nul && set "connected=1"
    if "!connected!"=="0" timeout /t 1 /nobreak > nul
)

"%WARPCLI%" status

if "!connected!"=="1" goto running

echo:
echo WARP did not report Connected.
if "!compatTried!"=="0" (
    echo Compatibility mode captures all ports and may help on strict networks.
    choice /c RCQ /n /m "[R] retry in Compatibility mode, [C] continue anyway, [Q] stop everything: "
    if errorlevel 3 goto cleanup
    if errorlevel 2 goto running
    set "compatTried=1"
    set "gfMode=all"
    set "gfTcp=%ALL_PORTS%"
    set "gfUdp=%ALL_PORTS%"
    "%WARPCLI%" disconnect > nul 2>&1
    call "%~dp0service.bat" remove_services_silent > nul 2>&1
    goto launch
)
choice /c CQ /n /m "[C] continue anyway, [Q] stop everything: "
if errorlevel 2 goto cleanup

:running
echo:
if "!connected!"=="1" if exist "%ROOT%utils\warp-quality.ps1" (
    echo Quick link quality check through the tunnel...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%utils\warp-quality.ps1" -Target 1.1.1.1 -Count 10
    echo:
    echo For your game server use "4 - CHECK ping and packet loss.bat".
)
echo:
echo Now start your game or game launcher (Steam, Epic, Battle.net, EA, Ubisoft, Riot, ...).
echo Keep this window open while you are playing.
echo:
echo When you finish playing, return to this window and press Enter.
echo WARP, Cloudflare One Client, zapret and WinDivert will be stopped.
set /p "stopChoice=Press Enter to stop everything..."

:cleanup
echo:
echo Disconnecting Cloudflare WARP...
if exist "%WARPCLI%" "%WARPCLI%" disconnect

echo Removing zapret and WinDivert services...
call "%~dp0service.bat" remove_services_silent

taskkill /IM "Cloudflare WARP.exe" /F > nul 2>&1

echo Everything has been stopped.
exit

:invalid_profile
echo ERROR: Invalid profile number.
pause
exit /b 1

:invalid_ports
echo ERROR: Ports may contain only digits, commas and dashes.
pause
exit /b 1
