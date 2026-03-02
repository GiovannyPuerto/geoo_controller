@echo off
setlocal

cd /d "%~dp0"

echo Directorio actual: %CD%
if not exist "%CD%\pubspec.yaml" (
    echo Error: no se encontro pubspec.yaml en %CD%.
    call :pauseAndExit 1
)

set "LOG=%~dp0build_installer.log"
echo ==== Inicio %DATE% %TIME% ==== > "%LOG%"
echo Directorio actual: %CD% >> "%LOG%"

set "ISCC="
set "ISS=%~dp0installer.iss"

REM ── Buscar ISCC.exe en rutas comunes ────────────────────────────────────────
if exist "C:\Users\%USERNAME%\AppData\Local\Programs\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Users\%USERNAME%\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
    goto :foundIscc
)
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    goto :foundIscc
)
if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
    goto :foundIscc
)
for /f "delims=" %%I in ('where ISCC.exe 2^>nul') do (
    set "ISCC=%%I"
    goto :foundIscc
)
:foundIscc

REM ── flutter pub get ─────────────────────────────────────────────────────────
echo.
echo [1/3] Obteniendo dependencias Flutter...
echo Ejecutando: flutter pub get >> "%LOG%"
call flutter pub get >> "%LOG%" 2>&1
if errorlevel 1 (
    echo Error: fallo flutter pub get.
    echo Error: fallo flutter pub get. >> "%LOG%"
    call :pauseAndExit 1
)
echo flutter pub get OK >> "%LOG%"

REM ── flutter build windows ───────────────────────────────────────────────────
echo.
echo [2/3] Compilando para Windows Release...
echo Ejecutando: flutter build windows --release >> "%LOG%"
call flutter build windows --release >> "%LOG%" 2>&1
if errorlevel 1 (
    echo Error: fallo la compilacion de Windows.
    echo Error: fallo la compilacion de Windows. >> "%LOG%"
    call :pauseAndExit 1
)
echo flutter build windows OK >> "%LOG%"

echo.
echo Compilacion completada. Ejecutable en:
echo   build\windows\x64\runner\Release\geo_inventario.exe
echo.

REM ── Inno Setup ──────────────────────────────────────────────────────────────
if not defined ISCC (
    echo Advertencia: no se encontro ISCC.exe. Se omite la generacion del instalador.
    echo Instala Inno Setup 6 desde https://jrsoftware.org/isdl.php
    call :pauseAndExit 0
)

if not exist "%ISS%" (
    echo Error: no se encontro installer.iss en %CD%.
    call :pauseAndExit 1
)

echo [3/3] Generando instalador con Inno Setup...
echo Ejecutando: "%ISCC%" "%ISS%" >> "%LOG%"
"%ISCC%" "%ISS%" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo Error: fallo la compilacion del instalador.
    echo.
    echo Ultimas lineas del log:
    powershell -NoProfile -Command "Get-Content -Path '%LOG%' -Tail 30"
    call :pauseAndExit 1
)
echo Inno Setup OK >> "%LOG%"

echo.
echo === Instalador generado en: installer_output\ ===
echo.

pause
exit /b 0

:pauseAndExit
echo.
pause
exit /b %1
