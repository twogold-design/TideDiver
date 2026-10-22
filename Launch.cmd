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
"D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --log-file "%~dp0artifacts\game.log" %*
endlocal
