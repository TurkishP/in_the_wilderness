@echo off
rem Starts the game. Uses the winget install of Godot if present, otherwise `godot` from PATH.
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe"
if not exist "%GODOT%" set "GODOT=godot"
"%GODOT%" --path "%~dp0."
