; Quorumly for Windows — per-user installer (Inno Setup 6).
;
; Built by scripts/package-windows.ps1, which passes the version, the package
; architecture, and the staged portable directory:
;   ISCC.exe /DAppVersion=1.0.0 /DArch=x86_64 /DPackageDir=<stage> /DOutputDir=<out> quorumly.iss
;
; Installs into %LOCALAPPDATA%\Programs\Quorumly without elevation, like VS
; Code's user setup: the directory stays writable by its user, so the in-app
; updater (crates/update/src/windows.rs) can replace quorumly.exe in place. The
; staged directory already carries quorumly-update.json, which marks the install
; as update-managed. Re-running a newer installer upgrades in place; user data
; lives in %LOCALAPPDATA%\Quorumly and is never touched here.

#ifndef AppVersion
  #error AppVersion must be defined (/DAppVersion=x.y.z)
#endif
#ifndef Arch
  #error Arch must be defined (/DArch=x86_64 or /DArch=aarch64)
#endif
#ifndef PackageDir
  #error PackageDir must be defined (/DPackageDir=<staged package directory>)
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#if Arch == "aarch64"
  #define ArchAllowed "arm64"
#else
  #define ArchAllowed "x64compatible"
#endif

[Setup]
; Identifies the installation across upgrades;
; crates/update/src/windows.rs refreshes DisplayVersion under this key after
; in-app updates.
AppId={{AD5DEC34-E254-467B-8F24-8127EBAF4DA6}
AppName=Quorumly
AppVersion={#AppVersion}
AppVerName=Quorumly {#AppVersion}
AppPublisher=Quorumly
AppPublisherURL=https://quorumly.org
AppSupportURL=https://github.com/soumyachk101/Quorumly/issues
AppUpdatesURL=https://github.com/soumyachk101/Quorumly/releases
VersionInfoVersion={#AppVersion}
PrivilegesRequired=lowest
DefaultDirName={autopf}\Quorumly
DisableProgramGroupPage=yes
DisableDirPage=auto
DisableReadyPage=yes
ArchitecturesAllowed={#ArchAllowed}
ArchitecturesInstallIn64BitMode={#ArchAllowed}
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=quorumly-{#AppVersion}-windows-{#Arch}-setup
SetupIconFile=quorumly.ico
UninstallDisplayIcon={app}\quorumly.exe
UninstallDisplayName=Quorumly
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; A running Quorumly is closed through the Restart Manager before its files are
; replaced; the updated app starts again from the finish page.
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PackageDir}\quorumly.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PackageDir}\quorumly-update.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PackageDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PackageDir}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PackageDir}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Quorumly"; Filename: "{app}\quorumly.exe"
Name: "{autodesktop}\Quorumly"; Filename: "{app}\quorumly.exe"; Tasks: desktopicon

[Registry]
; quorumly:// conversation links — the scheme registered for Quorumly
Root: HKCU; Subkey: "Software\Classes\quorumly"; ValueType: string; ValueName: ""; ValueData: "URL:Quorumly"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\quorumly"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\quorumly\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\quorumly.exe"",0"
Root: HKCU; Subkey: "Software\Classes\quorumly\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\quorumly.exe"" ""%1"""

[Run]
Filename: "{app}\quorumly.exe"; Description: "{cm:LaunchProgram,Quorumly}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Leftovers of in-app updates (crates/update/src/windows.rs).
Type: files; Name: "{app}\quorumly.exe.old"
Type: files; Name: "{app}\.quorumly-update-incoming.exe"
Type: filesandordirs; Name: "{app}\.quorumly-update-*"
