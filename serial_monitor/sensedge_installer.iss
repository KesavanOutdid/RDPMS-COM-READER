; APPLICATION FOR SENSEDGE - Inno Setup Script
; This script creates an installer for the APPLICATION FOR SENSEDGE build

#define MyAppName "APPLICATION FOR SENSEDGE"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "SENSEDGE"
#define MyAppExeName "serial_monitor.exe"

[Setup]
AppId={{A9E8D7C6-5B4A-3F2E-1D0C-9B8A7F6E5D4C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\installer_output
OutputBaseFilename=APPLICATION_FOR_SENSEDGE_Setup
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

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
