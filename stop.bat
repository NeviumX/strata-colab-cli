@echo off
rem Close the tunnel and stop the Colab runtime. The downloaded model is deleted too.
setlocal
chcp 65001 >nul
set "DISTRO_OPT="
if defined STRATA_WSL_DISTRO set "DISTRO_OPT=-d %STRATA_WSL_DISTRO%"
wsl.exe %DISTRO_OPT% --cd "%~dp0." -- bash -lc "bash ./down.sh"
echo.
pause
