; RDPMS Serial Monitor - Inno Setup Script
; This script creates an installer for the RDPMS Serial Monitor application

#define MyAppName "RDPMS Serial Monitor"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "RDPMS"
#define MyAppExeName "serial_monitor.exe"

[Setup]
AppId={{8F7A3E5C-2D4B-4F9E-A1C3-6B8E7D2F5A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\installer_output
OutputBaseFilename=RDPMS_Serial_Monitor_v{#MyAppVersion}_Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main executable and all DLLs
Source: "build\windows\x64\runner\Release\serial_monitor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_libserialport_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\serialport.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
; Data folder (flutter assets, fonts, etc.)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[InstallDelete]
Type: filesandordirs; Name: "{userappdata}\com.example\serial_monitor"
Type: filesandordirs; Name: "{localappdata}\com.example\serial_monitor"
Type: filesandordirs; Name: "{userappdata}\serial_monitor"
Type: filesandordirs; Name: "{localappdata}\serial_monitor"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*"
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{userappdata}\com.example\serial_monitor"
Type: filesandordirs; Name: "{localappdata}\com.example\serial_monitor"
Type: filesandordirs; Name: "{userappdata}\serial_monitor"
Type: filesandordirs; Name: "{localappdata}\serial_monitor"

[UninstallRun]
Filename: "reg.exe"; Parameters: "delete ""HKCU\Software\com.example\serial_monitor"" /f"; Flags: runhidden; RunOnceId: "DelRegKey1"
Filename: "reg.exe"; Parameters: "delete ""HKCU\Software\serial_monitor"" /f"; Flags: runhidden; RunOnceId: "DelRegKey2"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
