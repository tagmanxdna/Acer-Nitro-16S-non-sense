@echo off
:: ============================================================
:: ACER NITRO AN16S-61 - App Launcher (portable, admin auto)
:: ============================================================
chcp 65001 >nul
title Acer Nitro Control Center

:: Auto-elevation (ignore si UAC bloque)
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WindowStyle Hidden" >nul 2>&1
    if %errorLevel% EQU 0 ( exit /b )
    echo [WARN] Admin refuse - demarrage en mode limite
)

echo.
echo [ADMIN] Acer Nitro Control Center
echo ============================================
echo.

cd /d "%~dp0"

:: Detect Python 3
py -3 -c "exit()" >nul 2>&1
if %errorlevel% EQU 0 (
    py -3 "%~dp0acer_nitro_app.py" %*
    if errorlevel 1 if not errorlevel 9009 ( echo. & echo [ERREUR] App terminee avec erreur. & pause )
    exit /b
)

python -c "exit()" >nul 2>&1
if %errorlevel% EQU 0 (
    python "%~dp0acer_nitro_app.py" %*
    if errorlevel 1 if not errorlevel 9009 ( echo. & echo [ERREUR] App terminee avec erreur. & pause )
    exit /b
)

echo [ERREUR] Python 3 introuvable. Installez Python 3.x depuis python.org
pause
exit /b 1
