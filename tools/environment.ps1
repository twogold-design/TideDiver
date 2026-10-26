# Shared development environment. Generated logs and runtime data stay outside the submission.
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'src'
$work = Join-Path (Split-Path $root -Parent) ('.' + (Split-Path $root -Leaf) + '-web-work')
$env:APPDATA = Join-Path $work 'appdata'
$env:LOCALAPPDATA = Join-Path $work 'localappdata'
$env:TEMP = Join-Path $work 'temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $work,$env:APPDATA,$env:LOCALAPPDATA,$env:TEMP | Out-Null
if (!$Godot) { $Godot = $env:GODOT_BIN }
if (!$Godot) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $Godot = $command.Source }
}
if (!$Godot -and (Test-Path -LiteralPath 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')) {
    $Godot = 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
}
if (!$Godot -or !(Test-Path -LiteralPath $Godot)) { throw 'Install Godot 4.7.2 and pass -Godot or set GODOT_BIN to its executable.' }
Set-Location -LiteralPath $source
