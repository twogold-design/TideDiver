param(
    [ValidateRange(1024,65535)][int]$Port = 8060,
    [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$url = "http://127.0.0.1:$Port/"
$entry = Join-Path $root 'index.html'

try {
    if (-not (Test-Path -LiteralPath $entry)) { throw 'Web build missing. Run BuildWeb.cmd first.' }
    $expected = [IO.File]::ReadAllText($entry)
    function Test-Preview {
        try { $reply = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 }
        catch { return $false }
        if ($reply.StatusCode -eq 200 -and $reply.Content -ceq $expected) { return $true }
        throw "Port $Port is being used by another page. Close that preview and try again."
    }

    if (-not (Test-Preview)) {
        $node = Get-Command node.exe -ErrorAction SilentlyContinue
        if (-not $node) { throw 'Node.js is required for local preview. Install Node.js 20 or newer, then double-click Launch.cmd again.' }
        $work = Join-Path (Split-Path $root -Parent) '.TideDiver-web-work'
        $logs = Join-Path $work 'preview'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $previousPort = $env:PORT
        try {
            $env:PORT = "$Port"
            $preview = Start-Process -FilePath $node.Source -ArgumentList ('"' + (Join-Path $PSScriptRoot 'serve_web.cjs') + '"') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs "$Port-$PID.out.log") -RedirectStandardError (Join-Path $logs "$Port-$PID.err.log")
        } finally { $env:PORT = $previousPort }
        $ready = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            if (Test-Preview) { $ready = $true; break }
            if ($preview.HasExited) { throw "Preview could not start. See logs in $logs" }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) { throw "Preview did not become ready. See logs in $logs" }
    }
    if (-not $NoBrowser) { Start-Process -FilePath $url }
    Write-Output "Tide Diver is ready: $url"
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
