@echo off
rem coSHLink: double-click to open a window running coSHLink.sh --loop
rem (Windows Terminal, else mintty). Ctrl+C quits.
setlocal

set "SCRIPT=%~dp0coSHLink.sh"
set "SCRIPT=%SCRIPT:\=/%"

set "GIT="
for %%G in ("%ProgramFiles%\Git" "%ProgramFiles(x86)%\Git" "%LocalAppData%\Programs\Git") do (
  if not defined GIT if exist "%%~G\bin\bash.exe" set "GIT=%%~G"
)
if not defined GIT (
  echo No encuentro Git Bash. Instala Git for Windows: https://git-scm.com/download/win
  pause
  exit /b 1
)

where wt.exe >nul 2>&1
if not errorlevel 1 (
  start "" wt.exe -w new --size 80,24 new-tab --title coSHLink --suppressApplicationTitle "%GIT%\bin\bash.exe" -l "%SCRIPT%" --loop
  exit /b 0
)

start "" "%GIT%\usr\bin\mintty.exe" -s 80,24 -t coSHLink -o "Font=Cascadia Mono" -o Charset=UTF-8 -o Term=xterm-256color -e /usr/bin/bash -l "%SCRIPT%" --loop
