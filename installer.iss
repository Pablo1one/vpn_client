[Setup]
AppName=VPN Client
AppVersion=1.0.0
AppPublisher=vpn_client
DefaultDirName={autopf}\VPNClient
DefaultGroupName=VPN Client
OutputDir=D:\vpn_client\installer_output
OutputBaseFilename=VPNClient-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName=VPN Client
UninstallDisplayIcon={app}\vpn_client.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "D:\vpn_client\build\windows\x64\runner\Release\vpn_client.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\vpn_client\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\vpn_client\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VPN Client"; Filename: "{app}\vpn_client.exe"
Name: "{group}\Uninstall VPN Client"; Filename: "{uninstallexe}"
Name: "{commondesktop}\VPN Client"; Filename: "{app}\vpn_client.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vpn_client.exe"; Description: "Launch VPN Client"; Flags: nowait postinstall skipifsilent
