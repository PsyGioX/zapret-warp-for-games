# cleanup-helper.ps1 - helper for "5 - FULL UNINSTALL zapret-warp.bat" (local only, no downloads)
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckFolder', 'DefenderExclusions', 'UninstallWarp', 'HostsReport', 'RemoveFolder')]
    [string]$Action,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

function Get-UnsafeReason([string]$Path) {
    # Returns $null when the folder is safe to delete, otherwise a human-readable reason.
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'empty path' }
    try { $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return 'invalid path' }

    $driveRoot = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -ieq $driveRoot) { return 'it is a drive root' }

    $protected = @(
        $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
        $env:USERPROFILE, $env:PUBLIC,
        [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $env:USERPROFILE 'Downloads')
    ) | Where-Object { $_ }

    foreach ($p in $protected) {
        $pt = $p.TrimEnd('\')
        if ($full -ieq $pt) { return "it is a protected system folder ($pt)" }
        if ($pt.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return "it contains a protected folder ($pt)" }
    }

    foreach ($marker in @('service.bat', 'general.bat', 'bin\winws.exe', 'bin\WinDivert64.sys')) {
        if (-not (Test-Path -LiteralPath (Join-Path $full $marker))) {
            return "it does not look like a zapret-warp folder (missing $marker)"
        }
    }
    return $null
}

switch ($Action) {

    'CheckFolder' {
        $reason = Get-UnsafeReason $Root
        if ($reason) {
            Write-Host "  [WARN] The folder will NOT be deleted automatically: $reason" -ForegroundColor Yellow
            exit 2
        }
        exit 0
    }

    'DefenderExclusions' {
        try {
            $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
            $pref = Get-MpPreference
            $removed = 0
            foreach ($e in @($pref.ExclusionPath)) {
                if ($e -and (($e.TrimEnd('\') -ieq $full) -or $e.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
                    Remove-MpPreference -ExclusionPath $e
                    Write-Host "  [OK] Defender path exclusion removed: $e"
                    $removed++
                }
            }
            foreach ($e in @($pref.ExclusionProcess)) {
                if ($e -and $e.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                    Remove-MpPreference -ExclusionProcess $e
                    Write-Host "  [OK] Defender process exclusion removed: $e"
                    $removed++
                }
            }
            if ($removed -eq 0) { Write-Host '  [--] no Defender exclusions point to this folder' }
        } catch {
            Write-Host '  [--] Microsoft Defender settings are not available (third-party antivirus?) - check its exclusions manually' -ForegroundColor Yellow
        }
        exit 0
    }

    'UninstallWarp' {
        Get-Process -Name 'Cloudflare WARP' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $app = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Cloudflare WARP*' -or $_.DisplayName -like 'Cloudflare One Client*' } |
            Select-Object -First 1

        if (-not $app) {
            Write-Host '  [--] Cloudflare WARP is not installed'
            exit 3
        }

        Write-Host ("  Uninstalling: {0} {1}" -f $app.DisplayName, $app.DisplayVersion)
        $us = [string]$app.UninstallString
        $guid = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
        if ($us -match $guid) {
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $Matches[0], '/qn', '/norestart') -Wait -PassThru
            if ($p.ExitCode -eq 0) { exit 0 }
            if ($p.ExitCode -eq 3010 -or $p.ExitCode -eq 1641) { exit 10 }
            Write-Host ("  [WARN] msiexec returned code {0}" -f $p.ExitCode) -ForegroundColor Yellow
            exit 1
        }
        Write-Host '  [WARN] Non-MSI uninstaller - remove Cloudflare WARP from Windows Settings > Apps' -ForegroundColor Yellow
        exit 4
    }

    'HostsReport' {
        $hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
        if (-not (Test-Path -LiteralPath $hosts)) { Write-Host '  [--] hosts file not found'; exit 0 }
        $lines = @(Get-Content -LiteralPath $hosts |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') -and ($_ -notmatch '^\S+\s+localhost\s*$') })
        if ($lines.Count -eq 0) {
            Write-Host '  [OK] hosts has no custom entries'
        } else {
            Write-Host ("  [INFO] hosts has {0} custom entries. This package never edits hosts; if you pasted entries from a zapret repository, remove them manually:" -f $lines.Count)
            $lines | Select-Object -First 15 | ForEach-Object { Write-Host "         $_" }
            if ($lines.Count -gt 15) { Write-Host ("         ... and {0} more" -f ($lines.Count - 15)) }
            Write-Host "         File: $hosts"
        }
        exit 0
    }

    'RemoveFolder' {
        $reason = Get-UnsafeReason $Root
        if ($reason) {
            Write-Host "  [WARN] Folder not deleted: $reason" -ForegroundColor Yellow
            exit 2
        }
        $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        $esc = $full.Replace("'", "''")
        $cmd = "Start-Sleep -Seconds 4; for (`$i = 0; `$i -lt 10 -and (Test-Path -LiteralPath '$esc'); `$i++) { try { Remove-Item -LiteralPath '$esc' -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Seconds 3 } }"
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath 'powershell.exe' -WorkingDirectory $env:TEMP -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
        exit 0
    }
}
