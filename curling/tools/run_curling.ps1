param(
    [string]$Godot = "C:\Program Files\Godot\Godot.exe",
    [string]$ApiUrl = ""
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot executable not found: $Godot"
}
$arguments = @("--path", $workspace, "--editor", "res://curling/curling.tscn")
if ($ApiUrl) {
    $arguments += "--curling-api=$ApiUrl"
}
& $Godot @arguments

