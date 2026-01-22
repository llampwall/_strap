@echo off
setlocal enabledelayedexpansion

set "ARGS="

:loop
if "%~1"=="" goto run

if /I "%~1"=="--skip-install" (
  set "ARGS=!ARGS! -SkipInstall"
) else if /I "%~1"=="--template" (
  set "ARGS=!ARGS! -Template"
) else if /I "%~1"=="-t" (
  set "ARGS=!ARGS! -Template"
) else if /I "%~1"=="--path" (
  set "ARGS=!ARGS! -Path"
) else if /I "%~1"=="-p" (
  set "ARGS=!ARGS! -Path"
) else (
  set "ARGS=!ARGS! %~1"
)
shift
goto loop

:run
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0strap.ps1" %ARGS%
endlocal