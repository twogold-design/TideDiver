param([string]$Godot, [switch]$Package, [switch]$Release)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
$developmentSource = $source
$destination = $root
if ($Release) {
    # Never rewrite the development checkout to disable tools. Build an isolated
    # source snapshot so failure or interruption cannot leave local GM disabled.
    $releaseWork = Join-Path $work ('releases/' + [Guid]::NewGuid().ToString('N'))
    $source = Join-Path $releaseWork 'src'
    New-Item -ItemType Directory -Force $source | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $developmentSource -Recurse -File -Force) {
        $relative = $file.FullName.Substring($developmentSource.Length + 1)
        if ($relative.Replace('\','/') -match '(^|/)(\.godot|saves|artifacts|\.runtime)/') { continue }
        $target = Join-Path $source $relative
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
    $flag = Join-Path $source 'scripts/build_mode.gd'
    [IO.File]::WriteAllText($flag,"extends RefCounted`nconst GM_ENABLED := false`n",[Text.UTF8Encoding]::new($false))
    $destination = Join-Path $root '.runtime/release-client'
    $output = Join-Path $releaseWork 'export'
} else {
    $output = Join-Path $work 'export'
    if ([IO.File]::ReadAllText((Join-Path $source 'scripts/build_mode.gd')) -notmatch 'GM_ENABLED\s*:?=\s*true') {
        throw 'Development source must keep GM enabled; use -Release for a player build.'
    }
}
New-Item -ItemType Directory -Force $output | Out-Null
New-Item -ItemType Directory -Force $destination | Out-Null
& $Godot --headless --editor --path $source --log-file (Join-Path $work 'import.log') --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
if ($Release) {
    $releaseTestLog = Join-Path $releaseWork 'release-test.log'
    & $Godot --headless --path $source --log-file $releaseTestLog --script 'res://tests/test_release_flow.gd'
    if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $releaseTestLog -Pattern '^PASS:' -Quiet) -or (Select-String -LiteralPath $releaseTestLog -Pattern 'SCRIPT ERROR|FAIL:' -Quiet)) {
        throw 'Release GM lockout regression failed. No package may be produced.'
    }
}
& $Godot --headless --path $source --export-release Web (Join-Path $output 'index.html') --log-file (Join-Path $work 'export.log')
if ($LASTEXITCODE -ne 0) { throw 'Web export failed.' }
$runtimeNames = @('index.html','index.js','index.wasm','index.pck','index.audio.worklet.js','index.audio.position.worklet.js')
foreach ($name in $runtimeNames) {
    $file = Join-Path $output $name
    if (!(Test-Path -LiteralPath $file)) { throw "Missing runtime file: $name" }
    Copy-Item -LiteralPath $file -Destination (Join-Path $destination $name) -Force
}
foreach ($mobileAsset in @('mobile-controls.js','mobile-controls.css')) {
    Copy-Item -LiteralPath (Join-Path $source ('web/' + $mobileAsset)) -Destination (Join-Path $destination $mobileAsset) -Force
}
# Keep the generated entry clean in Git even when the exporter inserts blank placeholders.
$entryPath = Join-Path $destination 'index.html'
$entryHtml = [IO.File]::ReadAllText($entryPath)
$entryHtml = [regex]::Replace($entryHtml, '(?m)[ \t]+(?=\r?$)', '').TrimEnd() + "`n"
[IO.File]::WriteAllText($entryPath, $entryHtml, [Text.UTF8Encoding]::new($false))
& node (Join-Path $PSScriptRoot 'prepare_local.cjs') $destination
if ($LASTEXITCODE -ne 0) { throw 'Local-file resource bundling failed.' }
$runtimeNames += @('local-loader.js','local-data.js','mobile-controls.js','mobile-controls.css','index.wasm.gz.bin','index.pck.gz.bin')
Copy-Item -LiteralPath (Join-Path $source 'assets/fonts/OFL.txt') -Destination (Join-Path $destination 'FONT-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $source 'web/THIRD-PARTY-NOTICES.txt') -Destination $destination -Force
if ($Release) { Copy-Item -LiteralPath (Join-Path $root 'PLAY.txt') -Destination $destination -Force }
$bytes = (Get-ChildItem -LiteralPath $destination -File | Where-Object { $_.Name -in ($runtimeNames + @('FONT-LICENSE.txt','THIRD-PARTY-NOTICES.txt')) } | Measure-Object Length -Sum).Sum
if ($bytes -ge 200000000) { throw 'Web runtime exceeds 200 MB.' }
$mode = if ($Release) { 'release' } else { 'development' }
$buildInfo = @{ mode=$mode; gmEnabled=(!$Release); source=$source; destination=$destination }
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-info.json') -Encoding UTF8
Write-Output "Built $mode client: $bytes runtime bytes at $destination."
if ($Package) { & (Join-Path $PSScriptRoot 'package_web.ps1') -Godot $Godot }
