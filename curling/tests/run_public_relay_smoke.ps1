param(
    [string]$Godot = "C:\Program Files\Godot\Godot_console.exe"
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$relayProject = Join-Path $workspace "curling\server\relay_project"
$serverRoot = Join-Path $workspace "curling\server"
$port = Get-Random -Minimum 45000 -Maximum 55000
$roomId = [guid]::NewGuid().ToString("N")
$secret = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))
$ticketFile = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-tickets-{0}.json" -f [guid]::NewGuid().ToString("N"))
$report = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-relay-{0}.json" -f [guid]::NewGuid().ToString("N"))
$started = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$logFiles = [System.Collections.Generic.List[string]]::new()
$debugOutput = [System.Collections.Generic.List[string]]::new()

try {
    $previousPythonPath = $env:PYTHONPATH
    $previousNoBytecode = $env:PYTHONDONTWRITEBYTECODE
    $env:PYTHONPATH = $serverRoot
    $env:PYTHONDONTWRITEBYTECODE = "1"
    $ticketProcess = Start-Process -FilePath "python" -ArgumentList @((Join-Path $serverRoot "tests\make_smoke_tickets.py"), $roomId, $secret, $ticketFile) -WorkingDirectory $serverRoot -PassThru -WindowStyle Hidden
    $started.Add($ticketProcess)
    $ticketProcess.WaitForExit()
    if ($ticketProcess.ExitCode -ne 0) {
        throw "Could not create Relay smoke tickets"
    }
    $tickets = Get-Content -Raw -LiteralPath $ticketFile | ConvertFrom-Json

    $env:CURLING_ROOM_ID = $roomId
    $env:CURLING_RELAY_PORT = "$port"
    $env:CURLING_ADMISSION_SECRET = $secret
    $env:CURLING_MAX_CLIENTS = "8"
    $env:CURLING_PROTOCOL_VERSION = "2"
    $relayArgs = @("--headless", "--path", $relayProject, "--scene", "res://relay.tscn")
    $relayOut = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-relay-$roomId.out.log")
    $relayErr = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-relay-$roomId.err.log")
    $logFiles.Add($relayOut)
    $logFiles.Add($relayErr)
    $started.Add((Start-Process -FilePath $Godot -ArgumentList $relayArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $relayOut -RedirectStandardError $relayErr))
    Remove-Item Env:CURLING_ROOM_ID, Env:CURLING_RELAY_PORT, Env:CURLING_ADMISSION_SECRET, Env:CURLING_MAX_CLIENTS, Env:CURLING_PROTOCOL_VERSION -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600

    for ($index = 0; $index -lt 8; $index++) {
        $session = $tickets[$index]
        $peerArgs = @(
            "--headless", "--path", $workspace,
            "--scene", "res://curling/tests/network_smoke_peer.tscn", "--",
            "--curling-smoke-transport=public",
            "--curling-smoke-role=$($session.role)",
            "--curling-smoke-index=$index",
            "--curling-smoke-players=8",
            "--curling-smoke-port=$port",
            "--curling-smoke-ticket=$($session.ticket)",
            "--curling-smoke-nickname=$($session.nickname)"
        )
        if ($index -eq 0) {
            $peerArgs += "--curling-smoke-report=$report"
        }
        $peerOut = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-peer-$roomId-$index.out.log")
        $peerErr = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-peer-$roomId-$index.err.log")
        $logFiles.Add($peerOut)
        $logFiles.Add($peerErr)
        $started.Add((Start-Process -FilePath $Godot -ArgumentList $peerArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $peerOut -RedirectStandardError $peerErr))
        if ($index -eq 0) {
            Start-Sleep -Milliseconds 350
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $report) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $report)) {
        throw "Public Relay smoke timed out"
    }
    $result = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
    if (-not $result.ok -or $result.players -ne 8) {
        foreach ($logFile in $logFiles) {
            if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt 0) {
                $debugOutput.Add("[$([System.IO.Path]::GetFileName($logFile))]`n$(Get-Content -Raw -LiteralPath $logFile)")
            }
        }
        throw "Public Relay smoke failed: $(Get-Content -Raw -LiteralPath $report)`n$($debugOutput -join "`n")"
    }
    Write-Output "CURLING_PUBLIC_RELAY_SMOKE_OK players=$($result.players) port=$port"
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
            throw "Tracked Relay smoke process still running: PID $($process.Id)"
        }
    }
    Remove-Item -LiteralPath $ticketFile, $report -Force -ErrorAction SilentlyContinue
    foreach ($logFile in $logFiles) {
        Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
    }
    $env:PYTHONPATH = $previousPythonPath
    $env:PYTHONDONTWRITEBYTECODE = $previousNoBytecode
    Remove-Item Env:CURLING_ROOM_ID, Env:CURLING_RELAY_PORT, Env:CURLING_ADMISSION_SECRET, Env:CURLING_MAX_CLIENTS, Env:CURLING_PROTOCOL_VERSION -ErrorAction SilentlyContinue
}
