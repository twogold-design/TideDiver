@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0.runtime\appdata"
set "LOCALAPPDATA=%~dp0.runtime\localappdata"
set "TEMP=%~dp0.runtime\temp"
set "TMP=%~dp0.runtime\temp"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%TEMP%" mkdir "%TEMP%"
if not exist "%~dp0artifacts" mkdir "%~dp0artifacts"
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --log-file "%~dp0artifacts\progression-tests.log" --script res://tests/test_progression.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --log-file "%~dp0artifacts\restaurant-tests.log" --script res://tests/test_restaurant.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\integration-display-test.log" --script res://tests/test_game.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\restaurant-flow-tests.log" --script res://tests/test_restaurant_flow.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --log-file "%~dp0artifacts\layout-tests.log" --script res://tests/test_layout.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\layout-flow-tests.log" --script res://tests/test_layout_flow.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --log-file "%~dp0artifacts\furniture-catalog-tests.log" --script res://tests/test_furniture_catalog.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\new-game-tests.log" --script res://tests/test_new_game.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\living-world-tests.log" --script res://tests/test_living_world.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\hunting-tests.log" --script res://tests/test_hunting.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\dive-spawn-tests.log" --script res://tests/test_dive_spawns.gd
if errorlevel 1 exit /b 1
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --audio-driver Dummy --path "%~dp0." --log-file "%~dp0artifacts\ocean-feature-tests.log" --script res://tests/test_ocean_features.gd
if errorlevel 1 exit /b 1
endlocal





