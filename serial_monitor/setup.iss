[Setup]
; App Information
AppName=RDPMS CAN Analyzer
AppVersion=1.0.0
AppPublisher=RDPMS
AppCopyright=Copyright (C) 2026 RDPMS

; Installation Paths
DefaultDirName={autopf}\RDPMS CAN Analyzer
DefaultGroupName=RDPMS CAN Analyzer
DisableProgramGroupPage=yes

; Output Configuration
OutputDir=build\windows\setup
OutputBaseFilename=RDPMS_CAN_Analyzer_Setup
Compression=lzma2/ultra64
SolidCompression=yes

; Cosmetics
WizardStyle=modern

; Allow installation without admin rights if desired
PrivilegesRequired=lowest

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main executable and all dependencies from the Release folder
Source: "build\windows\x64\runner\Release\serial_monitor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu Shortcut
Name: "{group}\RDPMS CAN Analyzer"; Filename: "{app}\serial_monitor.exe"
; Desktop Shortcut
Name: "{autodesktop}\RDPMS CAN Analyzer"; Filename: "{app}\serial_monitor.exe"; Tasks: desktopicon

[Run]
; Run the app after setup finishes
Filename: "{app}\serial_monitor.exe"; Description: "{cm:LaunchProgram,RDPMS CAN Analyzer}"; Flags: nowait postinstall skipifsilent
