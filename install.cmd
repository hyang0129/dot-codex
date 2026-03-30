@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "CODEX_TARGET=%USERPROFILE%\.codex"
set "HOME_PLUGINS=%USERPROFILE%\plugins"
set "HOME_AGENTS=%USERPROFILE%\.agents\plugins"

if not exist "%CODEX_TARGET%" mkdir "%CODEX_TARGET%"
if not exist "%CODEX_TARGET%\skills" mkdir "%CODEX_TARGET%\skills"
if not exist "%CODEX_TARGET%\automations" mkdir "%CODEX_TARGET%\automations"
if not exist "%USERPROFILE%\.agents" mkdir "%USERPROFILE%\.agents"
if not exist "%HOME_AGENTS%" mkdir "%HOME_AGENTS%"
if not exist "%HOME_PLUGINS%" mkdir "%HOME_PLUGINS%"

echo Installing dot-codex from %SCRIPT_DIR%
echo.

call :linkfile "%SCRIPT_DIR%config.toml" "%CODEX_TARGET%\config.toml"
call :linkdir "%SCRIPT_DIR%skills" "%CODEX_TARGET%\skills"
call :linkdir "%SCRIPT_DIR%automations" "%CODEX_TARGET%\automations"
call :linkdir "%SCRIPT_DIR%plugins\issue-orchestrator" "%HOME_PLUGINS%\issue-orchestrator"
call :linkfile "%SCRIPT_DIR%.agents\plugins\marketplace.json" "%HOME_AGENTS%\marketplace.json"

echo.
echo Done. Codex settings live under %%USERPROFILE%%\.codex, and local plugin discovery lives under %%USERPROFILE%%\.agents and %%USERPROFILE%%\plugins.
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
