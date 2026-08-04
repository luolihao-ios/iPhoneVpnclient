#define MyAppName "Forge VPN"
#define MyAppVersion "0.1.1"
#define MyAppPublisher "Forge VPN"
#define MyAppExeName "forge_vpn_flutter.exe"

[Setup]
AppId={{B9D3F4F2-FA8B-4C29-8A71-8D43D7F9E4C1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Forge VPN
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=ForgeVPN-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式："

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "cache.db;*.log"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Forge VPN"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Forge VPN"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 Forge VPN"; Flags: nowait postinstall skipifsilent
