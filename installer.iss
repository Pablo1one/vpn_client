[Setup]
AppName=LightningMcQueen
AppVersion=1.0.0
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

[Files]
Source: "D:\vpn_client\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LightningMcQueen"; Filename: "{app}\LightningMcQueen.exe"
Name: "{group}\Uninstall LightningMcQueen"; Filename: "{uninstallexe}"
Name: "{commondesktop}\LightningMcQueen"; Filename: "{app}\LightningMcQueen.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\LightningMcQueen.exe"; Description: "Launch LightningMcQueen"; Flags: nowait postinstall skipifsilent
