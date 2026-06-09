[Setup]
AppName=LightningMcQueen
AppVersion=1.0.26
AppPublisher=LightningMcQueen
DefaultDirName={autopf}\LightningMcQueen
DefaultGroupName=LightningMcQueen
OutputDir=D:\vpn_client\installer_output
OutputBaseFilename=LightningMcQueen-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName=LightningMcQueen
UninstallDisplayIcon={app}\LightningMcQueen.exe
SetupIconFile=D:\vpn_client\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "autostart"; Description: "Launch LightningMcQueen at Windows startup"; GroupDescription: "Startup:"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "LightningMcQueen"; ValueData: """{app}\LightningMcQueen.exe"""; Flags: uninsdeletevalue; Tasks: autostart
; Task Manager: пометить автозапуск как включённый (0x02), иначе запись в Run игнорируется ("Отключено")
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueType: binary; ValueName: "LightningMcQueen"; ValueData: "02 00 00 00 00 00 00 00 00 00 00 00"; Flags: uninsdeletevalue; Tasks: autostart

[Files]
Source: "D:\vpn_client\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; движок + wintun кладём в {app}\bin (в pubspec их нет, чтобы не раздувать android apk)
Source: "D:\vpn_client\assets\bin\singbox-uni.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "D:\vpn_client\assets\bin\wintun.dll"; DestDir: "{app}\bin"; Flags: ignoreversion

[Icons]
Name: "{group}\LightningMcQueen"; Filename: "{app}\LightningMcQueen.exe"
Name: "{group}\Uninstall LightningMcQueen"; Filename: "{uninstallexe}"
Name: "{commondesktop}\LightningMcQueen"; Filename: "{app}\LightningMcQueen.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\LightningMcQueen.exe"; Description: "Launch LightningMcQueen"; Flags: nowait postinstall skipifsilent
