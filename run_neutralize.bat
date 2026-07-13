@echo off
:: ============================================================
::  Lanceur — acer_nitro_neutralize.ps1  (double-clic OK)
::  Un .ps1 ne s'execute PAS au double-clic (ouvre Notepad).
::  Ce .bat le lance correctement, avec menu + auto-admin.
:: ============================================================
chcp 65001 >nul
title Neutraliser Acer
cd /d "%~dp0"

set "PS1=%~dp0acer_nitro_neutralize.ps1"
if not exist "%PS1%" (
    echo [ERREUR] Introuvable : %PS1%
    pause & exit /b 1
)

:menu
cls
echo ============================================
echo   NEUTRALISER LES SERVICES ACER
echo ============================================
echo.
echo   1. Apercu       (DryRun - ne change rien)
echo   2. Appliquer    (coupe le bloat Acer)
echo   3. Appliquer +  taches planifiees
echo   4. Restaurer    (tout remettre)
echo   5. Quitter
echo.
set /p "CHOIX=Choix [1-5] : "

if "%CHOIX%"=="1" ( set "ARG=-DryRun" & goto run )
if "%CHOIX%"=="2" ( set "ARG=-Apply"  & goto run )
if "%CHOIX%"=="3" ( set "ARG=-Apply -IncludeTasks" & goto run )
if "%CHOIX%"=="4" ( set "ARG=-Restore" & goto run )
if "%CHOIX%"=="5" ( exit /b 0 )
goto menu

:run
echo.
echo [*] Lancement : %ARG%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %ARG%
echo.
pause
goto menu
