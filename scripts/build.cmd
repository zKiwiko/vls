@echo off
setlocal

REM Resolve script directory (includes trailing backslash)
set "script_dir=%~dp0"
set "out_dir=%script_dir%..\build"
set "vls_src=%script_dir%..\src"

REM Create output directory (no error if exists)
mkdir "%out_dir%" >nul 2>&1

REM Check for 'v' compiler in PATH
where v >nul 2>&1
if errorlevel 1 (
  echo error: 'v' compiler not found in PATH 1>&2
  endlocal
  exit /b 1
)

REM Output binary name on Windows
set "out_bin=%out_dir%\vls.exe"

REM Build; propagate failure
v -o "%out_bin%" "%vls_src%"
if errorlevel 1 (
  echo error: build failed 1>&2
  endlocal
  exit /b 1
)

echo Built: %out_bin%
endlocal
exit /b 0