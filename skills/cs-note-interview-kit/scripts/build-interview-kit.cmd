@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
node "%SCRIPT_DIR%build-interview-kit.mjs" %*
exit /b %errorlevel%
