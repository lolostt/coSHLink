@echo off
rem coSHLink launcher for Windows
rem
rem Double-click this file to open an 80x24 window running coSHLink.sh --loop.
rem Keep it in the same folder as coSHLink.sh. Press q or Ctrl+C to quit.
rem
rem It needs Git for Windows, which brings Git Bash. The window is a tab of
rem Windows Terminal if it is installed, and mintty (included with Git)
rem otherwise. Ctrl+C counts as a clean exit and closes the window; on an
rem error (a window too small, a missing tool) the window stays open.

setlocal EnableExtensions DisableDelayedExpansion

rem The script next to this file, with forward slashes for bash.
set "SCRIPT=%~dp0coSHLink.sh"
if not exist "%SCRIPT%" (
  echo coSHLink.sh was not found in "%~dp0".
  echo Download it into the same folder as this launcher.
  pause
  exit /b 1
)
set "SCRIPT=%SCRIPT:\=/%"

rem Find Git for Windows: first where its installer says it is, then the
rem usual folders, then the git.exe in the PATH (GIT\cmd\git.exe).
set "GIT="
for %%K in (HKLM HKCU) do if not defined GIT (
  for /f "tokens=2,*" %%A in ('reg query "%%K\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| find "InstallPath"') do (
    if exist "%%B\bin\bash.exe" set "GIT=%%B"
  )
)
for %%G in ("%ProgramFiles%\Git" "%ProgramW6432%\Git" "%ProgramFiles(x86)%\Git" "%LocalAppData%\Programs\Git") do (
  if not defined GIT if exist "%%~G\bin\bash.exe" set "GIT=%%~G"
)
if not defined GIT for /f "delims=" %%G in ('where git.exe 2^>nul') do (
  if not defined GIT if exist "%%~dpG..\bin\bash.exe" for %%R in ("%%~dpG..") do set "GIT=%%~fR"
)
if not defined GIT (
  echo Git Bash was not found. Install Git for Windows from https://gitforwindows.org/
  pause
  exit /b 1
)

rem In both terminals bash runs the script; exit 130 (Ctrl+C) becomes 0.
where /q wt.exe
if errorlevel 1 goto mintty

rem Windows Terminal keeps the tab open when the command fails.
start "" wt.exe -w new --size 80,24 new-tab --title coSHLink --suppressApplicationTitle "%GIT%\bin\bash.exe" -lc "\"$0\" --loop || [ $? = 130 ]" "%SCRIPT%"
exit /b 0

:mintty
rem mintty keeps the window open when the command fails (--hold error).
start "" "%GIT%\usr\bin\mintty.exe" -s 80,24 -t coSHLink --hold error -o "Font=Cascadia Mono" -o Charset=UTF-8 -o Term=xterm-256color -e /usr/bin/bash -lc "\"$0\" --loop || [ $? = 130 ]" "%SCRIPT%"
exit /b 0
