param([string]$Godot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
& $Godot --headless --editor --path $source --log-file (Join-Path $work 'test-import.log') --quit
if ($LASTEXITCODE -ne 0) { throw 'Import failed.' }
$tests = @('progression','restaurant','game','restaurant_flow','layout','layout_flow','furniture_catalog','new_game','living_world','hunting','dive_spawns','ocean_features','coastal_update','canyon_current','gm_dives')
foreach ($test in $tests) {
    $log = Join-Path $work ("test-$test.log")
    $options = @('--audio-driver','Dummy')
    if ($test -in @('progression','restaurant','layout','furniture_catalog')) { $options = @('--headless') }
    & $Godot @options --path $source --log-file $log --script "res://tests/test_$test.gd"
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL:' -Quiet)) { throw "Test failed: $test" }
}
