$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$zip = Join-Path (Split-Path $root -Parent) ((Split-Path $root -Leaf) + '-Web.zip')
# Include the complete web source, templates, tests and root entry; exclude generated/local data.
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
    $relative = $_.FullName.Substring($root.Length + 1).Replace('\','/')
    $relative -notmatch '(^|/)(\.git|\.godot|node_modules)/|^src/(tests/temp|saves|artifacts)/' -and $relative -notmatch '\.log$'
})
$bytes = ($files | Measure-Object Length -Sum).Sum
if ($bytes -ge 200000000) { throw "Full web project exceeds 200 MB: $bytes" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($zip,[IO.FileMode]::Create)
$archive = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose(); $stream.Dispose() }
$zipBytes = (Get-Item -LiteralPath $zip).Length
if ($zipBytes -ge 200000000) { throw 'ZIP exceeds 200 MB.' }
Write-Output "Complete web project: $bytes bytes, $($files.Count) files. ZIP: $zipBytes bytes at $zip"
