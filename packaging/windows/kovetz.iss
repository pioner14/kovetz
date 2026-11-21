#ifndef AppVersion
  #error "Supply /DAppVersion=<version> to ISCC."
#endif

[Setup]
AppId={{D05FC95B-CD14-45A7-A5BB-E7EE16B9B462}
AppName=Kovetz
AppVersion={#AppVersion}
AppPublisher=Nikolai Golotaistrov
DefaultDirName={autopf}\Kovetz
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\kovetz.exe
LicenseFile=..\..\LICENSE
OutputBaseFilename=kovetz-{#AppVersion}-windows-x64-setup
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Kovetz"; Filename: "{app}\kovetz.exe"
Name: "{autodesktop}\Kovetz"; Filename: "{app}\kovetz.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\kovetz.exe"; Description: "{cm:LaunchProgram,Kovetz}"; Flags: nowait postinstall skipifsilent
