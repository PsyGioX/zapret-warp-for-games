# warp-quality.ps1 - local latency / jitter / packet loss probe (no downloads, ICMP only)
param(
    [string]$Target = '1.1.1.1',
    [ValidateRange(1, 1000)][int]$Count = 20,
    [int]$TimeoutMs = 1000,
    [int]$IntervalMs = 200
)

$ping  = New-Object System.Net.NetworkInformation.Ping
$times = New-Object System.Collections.Generic.List[double]
$lost  = 0

Write-Host ("Probing {0} ({1} packets)..." -f $Target, $Count) -ForegroundColor Cyan

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

$min = ($times | Measure-Object -Minimum).Minimum
$max = ($times | Measure-Object -Maximum).Maximum
$avg = [math]::Round(($times | Measure-Object -Average).Average, 1)

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
Write-Host ("  Latency ms      : min {0}  avg {1}  max {2}" -f $min, $avg, $max)
Write-Host ("  Jitter ms       : {0}" -f $jitter)
Write-Host ""

if ($lost -eq 0 -and $jitter -le 10) {
    Write-Host "Verdict: clean link (no loss, low jitter)." -ForegroundColor Green
} elseif ($lost -eq 0) {
    Write-Host "Verdict: no loss, but jitter is high - try another profile or capture mode." -ForegroundColor Yellow
} else {
    Write-Host "Verdict: packet loss detected - try another profile, Compatibility mode, or re-run to rule out a one-off." -ForegroundColor Yellow
}
exit 0
