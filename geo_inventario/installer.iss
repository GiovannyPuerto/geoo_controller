#define MyAppName        "Dashboard de Inventario"
#define MyAppVersion     "1.0.0"
#define MyAppPublisher   "Geo Controller"
#define MyAppURL         "https://github.com/GiovannyPuerto/geoo_controller"
#define MyAppSupportURL  "https://github.com/GiovannyPuerto/geoo_controller/issues"
#define MyAppExeName     "geo_inventario.exe"
#define MyBuildDir       "build\windows\x64\runner\Release"
#define MyLicenseFile    "installer_assets\LICENSE.rtf"
#define MyIconFile       "windows\runner\resources\app_icon.ico"

; ─────────────────────────────────────────────────────────────────────────────
[Setup]
; ID único — NO cambiar entre versiones para que el actualizador funcione
AppId={{8F3C2A1D-4B7E-4F0A-9C5D-2E6F8A0B3D1C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=Copyright (C) 2026 {#MyAppPublisher}

; Instalación
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartIfNeededByRun=no

; Salida
OutputDir=installer_output
OutputBaseFilename=DashboardInventario_Setup_{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes

; Estilo y apariencia
WizardStyle=modern
WizardSizePercent=120
SetupIconFile={#MyIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Licencia y metadatos
LicenseFile={#MyLicenseFile}
ShowLanguageDialog=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Instalador de {#MyAppName}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

; ─────────────────────────────────────────────────────────────────────────────
[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

; ─────────────────────────────────────────────────────────────────────────────
[Messages]
WelcomeLabel1=Bienvenido al asistente de instalaci%ón de [name]
WelcomeLabel2=Este asistente le guiar%á a través de la instalaci%ón de [name/ver].%n%nSe recomienda cerrar todas las dem%ás aplicaciones antes de continuar.%n%nHaga clic en Siguiente para continuar.
FinishedHeadingLabel=Instalaci%ón de [name] completada
FinishedLabel=La instalaci%ón de [name] ha finalizado correctamente. La aplicaci%ón se puede iniciar desde los accesos directos creados.
ClickFinish=Haga clic en Finalizar para cerrar el asistente.

; ─────────────────────────────────────────────────────────────────────────────
[Tasks]
Name: "desktopicon"; \
    Description: "Crear un acceso directo en el &escritorio"; \
    GroupDescription: "Accesos directos adicionales:"; \
    Flags: unchecked

; ─────────────────────────────────────────────────────────────────────────────
[Files]
; Ejecutable principal
Source: "{#MyBuildDir}\{#MyAppExeName}"; \
    DestDir: "{app}"; Flags: ignoreversion

; DLLs del runtime Flutter/Windows
Source: "{#MyBuildDir}\*.dll"; \
    DestDir: "{app}"; Flags: ignoreversion

; Assets Flutter (carpeta data/)
Source: "{#MyBuildDir}\data\*"; \
    DestDir: "{app}\data"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; ─────────────────────────────────────────────────────────────────────────────
[Icons]
Name: "{group}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Desinstalar {#MyAppName}"; \
    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; \
    Tasks: desktopicon

; ─────────────────────────────────────────────────────────────────────────────
[Registry]
Root: HKLM; \
    Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{8F3C2A1D-4B7E-4F0A-9C5D-2E6F8A0B3D1C}_is1"; \
    ValueType: string; ValueName: "Publisher"; \
    ValueData: "{#MyAppPublisher}"; Flags: uninsdeletevalue
Root: HKLM; \
    Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{8F3C2A1D-4B7E-4F0A-9C5D-2E6F8A0B3D1C}_is1"; \
    ValueType: string; ValueName: "URLInfoAbout"; \
    ValueData: "{#MyAppSupportURL}"; Flags: uninsdeletevalue
Root: HKLM; \
    Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{8F3C2A1D-4B7E-4F0A-9C5D-2E6F8A0B3D1C}_is1"; \
    ValueType: string; ValueName: "DisplayVersion"; \
    ValueData: "{#MyAppVersion}"; Flags: uninsdeletevalue

; ─────────────────────────────────────────────────────────────────────────────
[Run]
Filename: "{app}\{#MyAppExeName}"; \
    Description: "Ejecutar {#MyAppName} ahora"; \
    Flags: nowait postinstall skipifsilent
