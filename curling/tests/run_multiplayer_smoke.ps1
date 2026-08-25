param(
    [string]$Godot = "C:\Program Files\Godot\Godot_console.exe",
    [ValidateRange(2, 8)]
    [int]$PlayerCount = 8,
    [int]$RttMs = 0,
    [double]$LossPercent = 0
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$port = Get-Random -Minimum 45000 -Maximum 55000
$report = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-smoke-{0}.json" -f [guid]::NewGuid().ToString("N"))
$started = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

try {
    $impairmentArgs = @("--curling-net-rtt-ms=$RttMs", "--curling-net-loss-percent=$LossPercent")
    $commonArgs = @("--curling-smoke-players=$PlayerCount", "--curling-smoke-port=$port") + $impairmentArgs
    $hostArgs = @("--headless", "--path", $workspace, "--scene", "res://curling/tests/network_smoke_peer.tscn", "--", "--curling-smoke-role=host", "--curling-smoke-report=$report") + $commonArgs
    $started.Add((Start-Process -FilePath $Godot -ArgumentList $hostArgs -PassThru -WindowStyle Hidden))
    Start-Sleep -Milliseconds 700
    for ($index = 1; $index -lt $PlayerCount; $index++) {
        $clientArgs = @("--headless", "--path", $workspace, "--scene", "res://curling/tests/network_smoke_peer.tscn", "--", "--curling-smoke-role=client", "--curling-smoke-index=$index") + $commonArgs
        $started.Add((Start-Process -FilePath $Godot -ArgumentList $clientArgs -PassThru -WindowStyle Hidden))
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $report) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $report)) {
        throw "$PlayerCount-player smoke timed out without a host report"
    }
    $result = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
    if (-not $result.ok -or $result.players -ne $PlayerCount) {
        throw "$PlayerCount-player smoke failed: $(Get-Content -Raw -LiteralPath $report)"
    }
    Write-Output "CURLING_MULTIPLAYER_SMOKE_OK players=$($result.players) port=$port rtt=${RttMs}ms loss=${LossPercent}%"
}
finally {
    foreach ($process in $started) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit(3000) | Out-Null
        }
    }
    foreach ($process in $started) {
        if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
            throw "Tracked Godot smoke process still running: PID $($process.Id)"
        }
    }
    Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
}
