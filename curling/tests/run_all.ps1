param(
    [string]$Godot = "C:\Program Files\Godot\Godot_console.exe",
    [switch]$SkipDependencyInstall
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$serverRoot = Join-Path $workspace "curling\server"
$venvRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("curling-tests-{0}" -f [guid]::NewGuid().ToString("N"))
$tracked = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Invoke-TrackedProcess {
    param([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory)
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden
    $tracked.Add($process)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Process failed with exit code $($process.ExitCode): $FilePath $($Arguments -join ' ')"
    }
}

try {
    Invoke-TrackedProcess $Godot @("--headless", "--path", $workspace, "--script", "res://curling/tests/run_unit_tests.gd") $workspace
    Invoke-TrackedProcess $Godot @("--headless", "--fixed-fps", "60", "--path", $workspace, "--scene", "res://curling/tests/native_physics_test.tscn") $workspace
    Invoke-TrackedProcess $Godot @("--headless", "--fixed-fps", "60", "--path", $workspace, "--scene", "res://curling/tests/stone_lifecycle_test.tscn") $workspace
    Invoke-TrackedProcess $Godot @("--headless", "--fixed-fps", "60", "--path", $workspace, "--scene", "res://curling/tests/native_calibration_test.tscn") $workspace
    Invoke-TrackedProcess $Godot @("--headless", "--fixed-fps", "60", "--path", $workspace, "--scene", "res://curling/tests/spin_distance_matrix_test.tscn") $workspace
    Invoke-TrackedProcess "python" @("-m", "venv", $venvRoot) $serverRoot
    $testPython = Join-Path $venvRoot "Scripts\python.exe"
    if (-not $SkipDependencyInstall) {
        Invoke-TrackedProcess $testPython @("-m", "pip", "install", "--disable-pip-version-check", "-r", (Join-Path $serverRoot "requirements.txt")) $serverRoot
    }
    $env:CURLING_MASTER_SECRET = "test-master-secret-for-runner-000000000000"
    $env:CURLING_RELAY_AUTOSTART = "0"
    $env:PYTHONDONTWRITEBYTECODE = "1"
    Invoke-TrackedProcess $testPython @("-m", "pytest") $serverRoot
    Write-Output "CURLING_ALL_TESTS_OK"
}
finally {
    foreach ($process in $tracked) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit(3000) | Out-Null
        }
    }
    foreach ($process in $tracked) {
        if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
            throw "Tracked verification process still running: PID $($process.Id)"
        }
    }
    if (Test-Path -LiteralPath $venvRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedVenv = [System.IO.Path]::GetFullPath($venvRoot)
        if (-not $resolvedVenv.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test venv outside the temporary directory: $resolvedVenv"
        }
        Remove-Item -LiteralPath $resolvedVenv -Recurse -Force
    }
    Remove-Item Env:CURLING_MASTER_SECRET -ErrorAction SilentlyContinue
    Remove-Item Env:CURLING_RELAY_AUTOSTART -ErrorAction SilentlyContinue
    Remove-Item Env:PYTHONDONTWRITEBYTECODE -ErrorAction SilentlyContinue
}
