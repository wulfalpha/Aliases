@echo off
:menu
cls
echo.
echo Network Troubleshooting Tools
echo =============================
echo.
echo 1 - Ping
echo 2 - Traceroute
echo 3 - PathPing
echo 4 - IP Configuration (Non-Admin)
echo 5 - Network Statistics
echo 6 - Flush DNS
echo.
echo 7 - IP Configuration (Admin)
echo 8 - Reset TCP/IP Stack (Admin)
echo 9 - Release and Renew IP (Admin)
echo.
echo q - Exit
echo.
set /p choice=Enter your choice:

if "%choice%"=="1" goto ping
if "%choice%"=="2" goto traceroute
if "%choice%"=="3" goto path
if "%choice%"=="4" goto ipconfig
if "%choice%"=="5" goto netstat
if "%choice%"=="6" goto flushdns
if "%choice%"=="7" goto admin
if "%choice%"=="8" goto reset_tcpip
if "%choice%"=="9" goto renew_ip
if "%choice%"=="q" goto end

goto menu

:ping
set /p host=Enter hostname or IP to ping:
ping %host%
pause
goto menu

:traceroute
set /p host=Enter hostname or IP for traceroute:
tracert %host%
pause
goto menu

:path
set /p host=Enter hostname or IP to ping with Statistics:
pathping %host%
pause
goto menu

:ipconfig
ipconfig
pause
goto menu

:netstat
netstat -a
pause
goto menu

:flushdns
ipconfig /flushdns
pause
goto menu

:admin
ipconfig /all
pause
goto menu

:reset_tcpip
netsh int ip reset resetlog.txt
pause
goto menu

:renew_ip
ipconfig /release
ipconfig /renew
pause
goto menu

:end
exit
