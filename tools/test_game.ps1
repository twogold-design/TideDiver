param([string]$Godot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
& $Godot --headless --editor --path $source --log-file (Join-Path $work 'test-import.log') --quit
if ($LASTEXITCODE -ne 0) { throw 'Import failed.' }
$tests = @('progression','restaurant','game','restaurant_flow','layout','layout_flow','furniture_catalog','new_game','living_world','hunting','dive_spawns','ocean_features','coastal_update','canyon_current','gm_dives','diver_motion','seabed_detail','dive_expansion','ray_wreck','canyon_wildlife','stonefish','depth_lighting','loot','transitions')
foreach ($test in $tests) {
    $log = Join-Path $work ("test-$test.log")
    $options = @('--audio-driver','Dummy')
    if ($test -in @('progression','restaurant','layout','furniture_catalog')) { $options = @('--headless') }
    & $Godot @options --path $source --log-file $log --script "res://tests/test_$test.gd"
    # Some Windows installations cannot read the OS certificate store. This exact
    # engine warning is unrelated to game tests; all other errors still fail.
    $testErrors = @(Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:' | Where-Object { $_.Line -ne 'ERROR: Failed to read the root certificate store.' })
    if ($LASTEXITCODE -ne 0 -or $testErrors.Count -gt 0 -or !(Select-String -LiteralPath $log -Pattern '^PASS:' -Quiet)) { throw "Test failed: $test" }
}
