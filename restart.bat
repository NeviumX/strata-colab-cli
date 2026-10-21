@echo off
rem After changing config.env or config.local.env, restart only Strata on the running Colab runtime.
rem The runtime and the downloaded model are kept. Keep this window open while you use Strata. It holds the SSH tunnel.
rem To use a non-default WSL distro, set STRATA_WSL_DISTRO, for example to Ubuntu-24.04.
setlocal
chcp 65001 >nul
set "DISTRO_OPT="
if defined STRATA_WSL_DISTRO set "DISTRO_OPT=-d %STRATA_WSL_DISTRO%"
title Strata on Colab
wsl.exe %DISTRO_OPT% --cd "%~dp0." -- bash -lc "bash ./restart.sh"
echo.
pause