@echo off
title Network Diagnostic Tool beta
del /q log.txt

:home
cls
echo.
ipconfig /all
netstat -o
echo __________________________________________________ >> log.txt
ipconfig /all >> log.txt
netstat -o >> log.txt

cls
echo.
echo Pick a tool:
echo __________________________________________________
echo.
echo 1) Flush dns
echo 2) Clear ip settings
echo 3) Nbtstat
echo 4) Renew ip settings
echo 5) Register dns
echo 6) Test Google.com
echo 7) Test Bing.com
echo 8) Test Yahoo.com
echo 9) Exit
echo *Requires Admin privilages

set /p web=select:
if "%web%"=="1" ipconfig /flushdns
if "%web%"=="1" ipconfig /flushdns >> log.txt
if "%web%"=="2" ipconfig /release
if "%web%"=="2" ipconfig /release >> log.txt
if "%web%"=="3" nbtstat -RR
if "%web%"=="3" nbtstat -RR >> log.txt
if "%web%"=="4" ipconfig /renew
if "%web%"=="4" ipconfig /renew >> log.txt
if "%web%"=="5" ipconfig /registerdns
if "%web%"=="5" ipconfig /registerdns >> log.txt
if "%web%"=="6" pathping www.google.com
if "%web%"=="7" pathping www.bing.com
if "%web%"=="8" pathping www.yahoo.com
if "%web%"=="6" pathping www.google.com >> log.txt
if "%web%"=="7" pathping www.bing.com >> log.txt
if "%web%"=="8" pathping www.yahoo.com >> log.txt
if "%web%"=="9" exit

pause
goto home
