@echo off
setlocal enabledelayedexpansion

REM Install dot-codex repo into %USERPROFILE%\.codex
REM Creates symlinks (requires admin or Developer Mode enabled)

set "SCRIPT_DIR=%~dp0"
set "TARGET=%USERPROFILE%\.codex"

if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\.agents" mkdir "%TARGET%\.agents"
if not exist "%TARGET%\.agents\plugins" mkdir "%TARGET%\.agents\plugins"

echo Installing dot-codex from %SCRIPT_DIR%
echo.

call :linkfile "%SCRIPT_DIR%config.toml" "%TARGET%\config.toml"
call :linkdir "%SCRIPT_DIR%skills" "%TARGET%\skills"
call :linkdir "%SCRIPT_DIR%plugins" "%TARGET%\plugins"
call :linkdir "%SCRIPT_DIR%automations" "%TARGET%\automations"
call :linkfile "%SCRIPT_DIR%.agents\plugins\marketplace.json" "%TARGET%\.agents\plugins\marketplace.json"

echo.
echo Done. Runtime state (auth, sessions, sqlite, caches, sandbox dirs, etc.) is untouched.
goto :eof

:backup
set "dst=%~1"
if exist "%dst%" (
    echo   backup: %dst% -^> %dst%.bak
    move /y "%dst%" "%dst%.bak" >nul 2>&1
)
goto :eof

:linkfile
set "src=%~1"
set "dst=%~2"
call :backup "%dst%"
mklink "%dst%" "%src%" >nul 2>&1
if errorlevel 1 (
    echo   copy:   %dst% - symlink failed, copying instead
    copy /y "%src%" "%dst%" >nul
) else (
    echo   linked: %dst% -^> %src%
)
goto :eof

:linkdir
set "src=%~1"
set "dst=%~2"
call :backup "%dst%"
mklink /D "%dst%" "%src%" >nul 2>&1
if errorlevel 1 (
    echo   copy:   %dst% - symlink failed, copying instead
    xcopy "%src%" "%dst%" /E /I /Y >nul
) else (
    echo   linked: %dst% -^> %src%
)
goto :eof
