@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
node "%SCRIPT_DIR%lint-cs-notes.mjs" %*
exit /b %errorlevel%
