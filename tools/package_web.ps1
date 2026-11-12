param([string]$Godot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$zip = Join-Path (Split-Path $root -Parent) ((Split-Path $root -Leaf) + '-Web.zip')
# Always produce a fresh release. Never package the developer's root preview.
# A separate PowerShell scope keeps build environment variables out of this script.
& (Join-Path $PSScriptRoot 'build_web.ps1') -Godot $Godot -Release
$clientRoot = Join-Path $root '.runtime/release-client'
$buildInfo = Get-Content -LiteralPath (Join-Path $clientRoot 'build-info.json') -Raw | ConvertFrom-Json
if ($buildInfo.mode -ne 'release' -or $buildInfo.gmEnabled -ne $false) { throw 'Refusing to package a development client.' }
# A complete playable client, not a development checkout: never ship tests,
# debug fixtures, editor templates, screenshots, source history or player saves.
$runtimeNames = @('index.html','index.js','index.wasm','index.pck',
    'index.wasm.gz.bin','index.pck.gz.bin','index.audio.worklet.js',
    'index.audio.position.worklet.js','local-loader.js','local-data.js',
    'mobile-controls.js','mobile-controls.css','FONT-LICENSE.txt',
    'THIRD-PARTY-NOTICES.txt','PLAY.txt')
$files = @($runtimeNames | ForEach-Object {
    $file = Join-Path $clientRoot $_
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing client file: $_. Rebuild before packaging." }
    Get-Item -LiteralPath $file
})
$bytes = ($files | Measure-Object Length -Sum).Sum
if ($bytes -ge 200000000) { throw "Web client exceeds 200 MB: $bytes" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($zip,[IO.FileMode]::Create)
$archive = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($clientRoot.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose(); $stream.Dispose() }
$zipBytes = (Get-Item -LiteralPath $zip).Length
if ($zipBytes -ge 200000000) { throw 'ZIP exceeds 200 MB.' }
Write-Output "Complete web client: $bytes bytes, $($files.Count) files. ZIP: $zipBytes bytes at $zip"
