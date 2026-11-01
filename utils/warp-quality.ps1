# warp-quality.ps1 - local latency / jitter / packet loss probe (no downloads, ICMP only)
#
# What changed vs. the first version:
#   * one discarded warm-up probe (the first packet through a fresh tunnel pays route/cache setup
#     and used to inflate "max" and "jitter");
#   * median, p95 and standard deviation next to min/avg/max, so one spike is not mistaken for
#     a bad link and a bad tail is not hidden by a good average;
#   * stricter verdict (jitter <= 5 ms is "excellent", <= 10 ms is "good");
#   * prints `warp-cli tunnel stats` (local, offline) when the Cloudflare client is installed.
#
# NOTE: ICMP to 1.1.1.1 through WARP measures you -> nearest Cloudflare edge. The path to a game
# server is longer; for that, run "4 - CHECK ping and packet loss.bat" with the game server IP.
param(
    [string]$Target = '1.1.1.1',
    [ValidateRange(1, 1000)][int]$Count = 20,
    [int]$TimeoutMs = 1000,
    [int]$IntervalMs = 200,
    [switch]$NoWarmup,
    [switch]$NoStats
)

$ping  = New-Object System.Net.NetworkInformation.Ping
$times = New-Object System.Collections.Generic.List[double]
$lost  = 0

Write-Host ("Probing {0} ({1} packets{2})..." -f $Target, $Count, $(if ($NoWarmup) { '' } else { ' + 1 warm-up' })) -ForegroundColor Cyan

if (-not $NoWarmup) {
    try { [void]$ping.Send($Target, $TimeoutMs) } catch { }
    Start-Sleep -Milliseconds $IntervalMs
}

for ($i = 1; $i -le $Count; $i++) {
    $reply = $null
    try { $reply = $ping.Send($Target, $TimeoutMs) } catch { $reply = $null }
    if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
        $times.Add([double]$reply.RoundtripTime)
    } else {
        $lost++
    }
    if ($i -lt $Count) { Start-Sleep -Milliseconds $IntervalMs }
}

$received = $times.Count
$lossPct  = [math]::Round(100.0 * $lost / $Count, 1)

if ($received -eq 0) {
    Write-Host ("Result: no replies from {0}. 100% loss (the host may block ICMP, or the tunnel is down)." -f $Target) -ForegroundColor Red
    exit 0
}

$sorted = @($times | Sort-Object)
$min = $sorted[0]
$max = $sorted[$received - 1]
$avg = [math]::Round(($times | Measure-Object -Average).Average, 1)

# median
if ($received % 2 -eq 1) { $median = $sorted[[int](($received - 1) / 2)] }
else { $median = ($sorted[$received / 2 - 1] + $sorted[$received / 2]) / 2 }

# p95, nearest-rank method
$rank = [int][math]::Ceiling(0.95 * $received)
if ($rank -lt 1) { $rank = 1 }
$p95 = $sorted[$rank - 1]

# standard deviation (population)
$var = 0.0
foreach ($t in $times) { $var += [math]::Pow($t - $avg, 2) }
$stdev = [math]::Round([math]::Sqrt($var / $received), 1)

# jitter = mean absolute difference between consecutive replies
$jitter = 0.0
if ($received -gt 1) {
    $sum = 0.0
    for ($k = 1; $k -lt $received; $k++) { $sum += [math]::Abs($times[$k] - $times[$k - 1]) }
    $jitter = [math]::Round($sum / ($received - 1), 1)
}

Write-Host ""
Write-Host ("  Sent / received : {0} / {1}" -f $Count, $received)
Write-Host ("  Packet loss     : {0}%" -f $lossPct)
Write-Host ("  Latency ms      : min {0}  median {1}  avg {2}  p95 {3}  max {4}" -f $min, $median, $avg, $p95, $max)
Write-Host ("  Std deviation   : {0} ms" -f $stdev)
Write-Host ("  Jitter ms       : {0}" -f $jitter)
Write-Host ""

if ($lost -eq 0 -and $jitter -le 5) {
    Write-Host "Verdict: excellent link (no loss, jitter <= 5 ms)." -ForegroundColor Green
} elseif ($lost -eq 0 -and $jitter -le 10) {
    Write-Host "Verdict: good link (no loss, jitter <= 10 ms). Fine for most games; very competitive shooters prefer jitter <= 5 ms." -ForegroundColor Green
} elseif ($lost -eq 0) {
    Write-Host "Verdict: no loss, but jitter is high - try another profile, close background downloads/Wi-Fi roaming, or re-run." -ForegroundColor Yellow
} else {
    Write-Host "Verdict: packet loss detected - try another profile, Compatibility mode, or re-run to rule out a one-off." -ForegroundColor Yellow
}
if ($received -gt 1 -and ($p95 - $median) -gt 15) {
    Write-Host ("Note: the tail is long (p95 {0} ms vs median {1} ms) - look for periodic spikes (Wi-Fi scans, background traffic, power saving)." -f $p95, $median) -ForegroundColor Yellow
}

if (-not $NoStats) {
    $cli = 'C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe'
    if (Test-Path -LiteralPath $cli) {
        try {
            $stats = & $cli tunnel stats 2>$null
            if ($stats) {
                Write-Host ""
                Write-Host "WARP tunnel stats (warp-cli tunnel stats):" -ForegroundColor Cyan
                $stats | ForEach-Object { Write-Host ("  {0}" -f $_) }
            }
        } catch { }
    }
}
exit 0
