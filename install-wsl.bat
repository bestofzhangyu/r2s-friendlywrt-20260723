@echo off
title WSL2 + Ubuntu Installer (R2S Build Env)
REM Right-click this file -^> Run as administrator

REM Check admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Admin privileges required!
    echo Right-click this file, select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  WSL2 + Ubuntu Installer for R2S Build
echo ============================================
echo.

echo [1/2] Installing WSL2 platform and kernel...
wsl --install --no-distribution
if %errorlevel% neq 0 (
    echo.
    echo [WARN] Non-zero exit code. Reboot may be required.
    echo If prompted to reboot, reboot and run this script again.
) else (
    echo [OK] WSL2 platform installed
)

echo.
echo [2/2] Installing Ubuntu distro (no-launch)...
wsl --install -d Ubuntu --no-launch
if %errorlevel% neq 0 (
    echo.
    echo [WARN] Non-zero exit code. Reboot may be required.
) else (
    echo [OK] Ubuntu distro installed
)

echo.
echo ============================================
echo  Installation complete!
echo ============================================
echo.
echo Next steps:/r/necho   1. Reboot if prompted
echo   2. Open Ubuntu from Start Menu
echo   3. Set Linux username and password
echo   4. Go back to WorkBuddy
echo.
pause
