@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
node "%SCRIPT_DIR%validate-mermaid.mjs" %*
exit /b %errorlevel%
