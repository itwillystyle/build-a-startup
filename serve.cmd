@echo off
rem Double-click: starts the Rojo sync server. Then in Studio: Plugins > Rojo > Connect.
cd /d "%~dp0"
"%USERPROFILE%\.rokitinojo.exe" serve default.project.json
pause
