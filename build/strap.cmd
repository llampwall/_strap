@echo off
setlocal enabledelayedexpansion

set "ARGS="

:loop
if "%~1"=="" goto run

if /I "%~1"=="--skip-install" (
  set "ARGS=!ARGS! -SkipInstall"
) else if /I "%~1"=="--install" (
  set "ARGS=!ARGS! -Install"
) else if /I "%~1"=="-Install" (
  set "ARGS=!ARGS! -Install"
) else if /I "%~1"=="--start" (
  set "ARGS=!ARGS! -Start"
) else if /I "%~1"=="-Start" (
  set "ARGS=!ARGS! -Start"
) else if /I "%~1"=="--keep" (
  set "ARGS=!ARGS! -Keep"
) else if /I "%~1"=="--strap-root" (
  set "ARGS=!ARGS! -StrapRoot"
) else if /I "%~1"=="--template" (
  set "ARGS=!ARGS! -Template"
) else if /I "%~1"=="-t" (
  set "ARGS=!ARGS! -Template"
) else if /I "%~1"=="--path" (
  set "ARGS=!ARGS! -Path"
) else if /I "%~1"=="-p" (
  set "ARGS=!ARGS! -Path"
) else if /I "%~1"=="--source" (
  set "ARGS=!ARGS! -Source"
) else if /I "%~1"=="--message" (
  set "ARGS=!ARGS! -Message"
) else if /I "%~1"=="--push" (
  set "ARGS=!ARGS! -Push"
) else if /I "%~1"=="--force" (
  set "ARGS=!ARGS! -Force"
) else if /I "%~1"=="--allow-dirty" (
  set "ARGS=!ARGS! -AllowDirty"
) else (
  set "ARGS=!ARGS! %~1"
)
shift
goto loop

:run
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0strap.ps1" %ARGS%
endlocal
