param([string]$Godot, [switch]$Package)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
$output = Join-Path $work 'export'
New-Item -ItemType Directory -Force $output | Out-Null
& $Godot --headless --editor --path $source --log-file (Join-Path $work 'import.log') --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& $Godot --headless --path $source --export-release Web (Join-Path $output 'index.html') --log-file (Join-Path $work 'export.log')
if ($LASTEXITCODE -ne 0) { throw 'Web export failed.' }
$runtimeNames = @('index.html','index.js','index.wasm','index.pck','index.audio.worklet.js','index.audio.position.worklet.js')
foreach ($name in $runtimeNames) {
    $file = Join-Path $output $name
    if (!(Test-Path -LiteralPath $file)) { throw "Missing runtime file: $name" }
    Copy-Item -LiteralPath $file -Destination (Join-Path $root $name) -Force
}
# Keep the generated entry clean in Git even when the exporter inserts blank placeholders.
$entryPath = Join-Path $root 'index.html'
$entryHtml = [IO.File]::ReadAllText($entryPath)
$entryHtml = [regex]::Replace($entryHtml, '(?m)[ \t]+(?=\r?$)', '').TrimEnd() + "`n"
[IO.File]::WriteAllText($entryPath, $entryHtml, [Text.UTF8Encoding]::new($false))
& node (Join-Path $PSScriptRoot 'prepare_local.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Local-file resource bundling failed.' }
$runtimeNames += @('local-loader.js','local-data.js')
Copy-Item -LiteralPath (Join-Path $source 'assets/fonts/OFL.txt') -Destination (Join-Path $root 'FONT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $source 'web/THIRD-PARTY-NOTICES.txt') -Destination $root -Force
$bytes = (Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Name -in ($runtimeNames + @('FONT-LICENSE.txt','THIRD-PARTY-NOTICES.txt')) } | Measure-Object Length -Sum).Sum
if ($bytes -ge 200000000) { throw 'Web runtime exceeds 200 MB.' }
Write-Output "Built root index.html: $bytes runtime bytes. Source: src/project.godot."
if ($Package) { & (Join-Path $PSScriptRoot 'package_web.ps1') }
