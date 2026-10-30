@echo off
chcp 65001 > nul
title FULL UNINSTALL - zapret-warp
setlocal EnableExtensions EnableDelayedExpansion

fltmc > nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "ROOT=%~dp0"
set "ROOT=!ROOT:~0,-1!"
set "HELPER=%~dp0utils\cleanup-helper.ps1"
set "WARPCLI=C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe"
set "helperOK=0"
if exist "!HELPER!" set "helperOK=1"

echo ================================================================
echo   FULL UNINSTALL / CLEANUP of zapret-warp
echo ================================================================
echo:
echo This will:
echo   - disconnect Cloudflare WARP and close its window
echo   - stop winws.exe
echo   - remove services zapret, WinDivert, WinDivert14 and their registry keys
echo   - remove temporary leftovers and Defender exclusions for this folder
echo   - list custom hosts-file entries for manual review (hosts is NOT edited)
echo:
echo Folder: !ROOT!
echo:
echo   1. Clean the system, keep this folder
echo   2. Clean the system AND delete this folder
echo   3. Cancel
choice /c 123 /n /m "Select 1-3: "
if errorlevel 3 goto cancelled
set "delFolder=0"
if errorlevel 2 set "delFolder=1"

if "!delFolder!"=="1" (
    if "!helperOK!"=="0" (
        echo ERROR: utils\cleanup-helper.ps1 is missing, the folder cannot be deleted safely.
        echo Continuing with system cleanup only.
        set "delFolder=0"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -File "!HELPER!" -Action CheckFolder -Root "!ROOT!"
        if errorlevel 1 (
            echo Continuing with system cleanup only.
            set "delFolder=0"
        )
    )
)

echo:
set "rmWarp=0"
choice /c YN /n /m "Also UNINSTALL Cloudflare WARP itself? [Y/N]: "
if not errorlevel 2 set "rmWarp=1"

set "revertTs=0"
echo:
echo zapret turns TCP timestamps on. The Windows default is off.
choice /c YN /n /m "Set TCP timestamps back to the Windows default? [Y/N]: "
if not errorlevel 2 set "revertTs=1"

echo:
if "!delFolder!"=="1" (
    echo The folder above and everything inside it will be PERMANENTLY deleted.
    set "confirm="
    set /p "confirm=Type DELETE to confirm: "
    if /i not "!confirm!"=="DELETE" goto cancelled
) else (
    choice /c YN /n /m "Start cleanup? [Y/N]: "
    if errorlevel 2 goto cancelled
)

echo:
echo [1/8] Cloudflare WARP
if exist "%WARPCLI%" (
    "%WARPCLI%" disconnect > nul 2>&1
    echo   [OK] disconnect command sent
) else (
    echo   [--] warp-cli not found
)
taskkill /IM "Cloudflare WARP.exe" /F > nul 2>&1

echo [2/8] zapret process
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if errorlevel 1 (
    echo   [--] winws.exe is not running
) else (
    taskkill /IM winws.exe /F > nul 2>&1
    echo   [OK] winws.exe stopped
)

echo [3/8] Services
for %%S in (zapret WinDivert WinDivert14) do (
    sc query "%%S" > nul 2>&1
    if errorlevel 1 (
        echo   [--] %%S is not registered
    ) else (
        net stop "%%S" > nul 2>&1
        sc delete "%%S" > nul 2>&1
        echo   [OK] %%S removed
    )
)

echo [4/8] Registry leftovers
for %%S in (zapret WinDivert WinDivert14) do (
    reg query "HKLM\System\CurrentControlSet\Services\%%S" > nul 2>&1
    if not errorlevel 1 (
        reg delete "HKLM\System\CurrentControlSet\Services\%%S" /f > nul 2>&1
        if errorlevel 1 (
            echo   [WARN] %%S key is locked until restart
        ) else (
            echo   [OK] %%S key deleted
        )
    )
)

echo [5/8] Temporary files and Defender exclusions
del /f /q "%TEMP%\zapret_hosts.txt" > nul 2>&1
del /f /q "%TEMP%\WinDivert*.sys" > nul 2>&1
echo   [OK] temp leftovers removed
if "!helperOK!"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!HELPER!" -Action DefenderExclusions -Root "!ROOT!"
) else (
    echo   [--] helper missing, Defender exclusions not checked
)

echo [6/8] TCP timestamps
if "!revertTs!"=="1" (
    netsh interface tcp set global timestamps=disabled > nul 2>&1
    if errorlevel 1 (
        echo   [WARN] could not change TCP timestamps
    ) else (
        echo   [OK] TCP timestamps set to the Windows default
    )
) else (
    echo   [--] skipped by choice
)

echo [7/8] Cloudflare WARP uninstall
if "!rmWarp!"=="1" (
    if "!helperOK!"=="1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "!HELPER!" -Action UninstallWarp
        set "rc=!errorlevel!"
        if "!rc!"=="0" echo   [OK] Cloudflare WARP uninstalled
        if "!rc!"=="10" echo   [OK] Cloudflare WARP uninstalled, restart Windows to finish
    ) else (
        echo   [WARN] helper missing, uninstall WARP from Windows Settings
    )
) else (
    echo   [--] skipped by choice, WARP stays installed
)

echo [8/8] hosts file
if "!helperOK!"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!HELPER!" -Action HostsReport
) else (
    echo   [--] helper missing
)

echo:
echo ---------------- Verification ----------------
set "problems=0"
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if not errorlevel 1 (
    echo   [WARN] winws.exe is still running
    set /a problems+=1
)
for %%S in (zapret WinDivert WinDivert14) do (
    sc query "%%S" > nul 2>&1
    if not errorlevel 1 (
        echo   [WARN] service %%S is still registered
        set /a problems+=1
    )
)
if "!problems!"=="0" (
    echo   [OK] no zapret processes or services left
) else (
    echo   Restart Windows to finish removing the items above.
)

if "!delFolder!"=="1" (
    echo:
    powershell -NoProfile -ExecutionPolicy Bypass -File "!HELPER!" -Action RemoveFolder -Root "!ROOT!"
    if errorlevel 1 (
        echo   Delete the folder manually: !ROOT!
        pause
        exit /b 1
    )
    cd /d "%TEMP%"
    echo   The folder will be removed a few seconds after this window closes.
    timeout /t 5 /nobreak > nul
    exit
)

echo:
echo Cleanup finished. You can delete this folder manually.
pause
exit /b 0

:cancelled
echo:
echo Cancelled. Nothing was changed.
pause
exit /b 0
