@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================
echo   Build EXE - Geo Inventario (Windows)
echo ==========================================

set "ROOT_DIR=%~dp0"
set "APP_NAME=Geo Inventario"
set "APP_EXE=geo_inventario.exe"
set "FLUTTER_DIR=%ROOT_DIR%geo_inventario"
set "RELEASE_DIR=%FLUTTER_DIR%build\windows\x64\runner\Release"
set "DIST_ROOT=%ROOT_DIR%dist"
set "DIST_DIR=%DIST_ROOT%\GeoInventario"
set "INSTALLER_DIR=%DIST_ROOT%\installer"
set "ISS_TEMP=%TEMP%\geo_inventario_installer.iss"
set "INNO_COMPILER="
set "APP_VERSION=1.0.0"
set "PUSHED=0"

if not exist "%FLUTTER_DIR%\pubspec.yaml" (
  echo [ERROR] No se encontro el proyecto Flutter en:
  echo         %FLUTTER_DIR%
  exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Flutter no esta en el PATH.
  echo         Instala Flutter y agrega flutter\bin al PATH.
  exit /b 1
)

pushd "%FLUTTER_DIR%"
if errorlevel 1 (
  echo [ERROR] No fue posible entrar a la carpeta del proyecto Flutter.
  exit /b 1
)
set "PUSHED=1"

for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /b /c:"version:" "%FLUTTER_DIR%\pubspec.yaml"`) do (
  set "RAW_VERSION=%%B"
)
if defined RAW_VERSION (
  set "RAW_VERSION=!RAW_VERSION: =!"
  for /f "tokens=1 delims=+" %%V in ("!RAW_VERSION!") do set "APP_VERSION=%%V"
)

echo [1/6] flutter clean
call flutter clean
if errorlevel 1 goto :fail

echo [2/6] flutter pub get
call flutter pub get
if errorlevel 1 goto :fail

echo [3/6] flutter build windows --release
call flutter build windows --release
if errorlevel 1 goto :fail

if not exist "%RELEASE_DIR%" (
  echo [ERROR] No se encontro la salida de compilacion en:
  echo         %RELEASE_DIR%
  goto :fail
)

echo [4/6] Copiando build a carpeta de distribucion...
if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
mkdir "%DIST_DIR%"
xcopy "%RELEASE_DIR%\*" "%DIST_DIR%\" /E /I /Y >nul
if errorlevel 1 goto :fail

if not exist "%INSTALLER_DIR%" mkdir "%INSTALLER_DIR%"

where ISCC >nul 2>&1
if not errorlevel 1 (
  for /f "delims=" %%I in ('where ISCC') do (
    if not defined INNO_COMPILER set "INNO_COMPILER=%%~fI"
  )
)
if not defined INNO_COMPILER if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "INNO_COMPILER=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined INNO_COMPILER if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "INNO_COMPILER=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if not defined INNO_COMPILER (
  echo [ERROR] No se encontro ISCC.exe (Inno Setup Compiler).
  echo         Instala Inno Setup 6 o agrega ISCC al PATH.
  goto :fail
)

echo [5/6] Generando script temporal de Inno Setup...
(
  echo #define MyAppName "%APP_NAME%"
  echo #define MyAppVersion "%APP_VERSION%"
  echo #define MyAppPublisher "Geo Inventario"
  echo #define MyAppExeName "%APP_EXE%"
  echo.
  echo [Setup]
  echo AppId={{B8BA0E17-48A1-4B78-9F0C-13A1C40D17C9}
  echo AppName={#MyAppName}
  echo AppVersion={#MyAppVersion}
  echo AppPublisher={#MyAppPublisher}
  echo DefaultDirName={autopf}\{#MyAppName}
  echo DisableProgramGroupPage=yes
  echo OutputDir=%INSTALLER_DIR%
  echo OutputBaseFilename=Setup-GeoInventario-%APP_VERSION%
  echo Compression=lzma
  echo SolidCompression=yes
  echo WizardStyle=modern
  echo.
  echo [Languages]
  echo Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
  echo.
  echo [Tasks]
  echo Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Tareas adicionales:"; Flags: unchecked
  echo.
  echo [Files]
  echo Source: "%DIST_DIR%\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
  echo.
  echo [Icons]
  echo Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
  echo Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
  echo.
  echo [Run]
  echo Filename: "{app}\{#MyAppExeName}"; Description: "Iniciar {#MyAppName}"; Flags: nowait postinstall skipifsilent
) > "%ISS_TEMP%"

echo [6/6] Compilando instalador con Inno Setup...
"%INNO_COMPILER%" "%ISS_TEMP%"
if errorlevel 1 goto :fail

if exist "%ISS_TEMP%" del /q "%ISS_TEMP%"

if "%PUSHED%"=="1" popd

echo.
echo [OK] Build completado.
echo      Ejecutable y dependencias en:
echo      %DIST_DIR%
echo.
echo Archivo principal:
echo      %DIST_DIR%\%APP_EXE%
echo.
echo Instalador generado en:
echo      %INSTALLER_DIR%\Setup-GeoInventario-%APP_VERSION%.exe
echo.
exit /b 0

:fail
set "ERR=%ERRORLEVEL%"
if exist "%ISS_TEMP%" del /q "%ISS_TEMP%" >nul 2>&1
if "%PUSHED%"=="1" popd
echo.
echo [ERROR] Fallo el proceso de build. Codigo: %ERR%
exit /b %ERR%
