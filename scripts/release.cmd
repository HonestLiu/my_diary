@echo off
rem One-command release wrapper for Windows cmd / PowerShell.
rem Real logic lives in scripts/release.mjs (cross-platform Node).
rem Usage: scripts\release [patch|minor|major|x.y.z|--dry-run]
setlocal
node "%~dp0release.mjs" %*
exit /b %ERRORLEVEL%
