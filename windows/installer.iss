; Inno Setup script for Nishant's DSA Setup (Windows).
; Build: iscc /DAppVer=1.0.0 windows\installer.iss  ->  dist\NishantsDSASetup-Windows.exe

#ifndef AppVer
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{8F3C2B71-6D0E-4C55-9C7A-2E5B1D9A4F10}
AppName=Nishant's DSA Setup
AppVersion={#AppVer}
AppVerName=Nishant's DSA Setup {#AppVer}
AppPublisher=Nishant
AppPublisherURL=https://github.com/GamerNishant/nishants-dsa-setup
DefaultDirName={localappdata}\NishantDSASetup\app
DisableDirPage=yes
DefaultGroupName=Nishant's DSA Setup
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=NishantsDSASetup-Windows
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayName=Nishant's DSA Setup
CloseApplications=no

[Messages]
WelcomeLabel2=This sets up a complete C++ / DSA environment like Nishant's:%n%n  - Visual Studio Code%n  - Modern g++ compiler (GCC)%n  - Nerd Font terminal prompt and coding fonts%n  - CPH Plus, C/C++ and Code Runner extensions%n  - Theme, editor settings and C++ snippets%n%nSteps that are already done on this PC are skipped. Your existing settings are backed up first, and you can undo everything later from the Start menu or by uninstalling this app.%n%nA PowerShell window will open and show the progress. Keep it open until it says "All done".
FinishedLabel=The setup has finished. Close all VS Code and terminal windows and open VS Code again to see the new setup.

[Files]
Source: "*.ps1"; DestDir: "{app}\windows"; Flags: ignoreversion
Source: "..\payload\*"; DestDir: "{app}\payload"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Run Nishant's DSA Setup again"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\setup.ps1"""; WorkingDir: "{app}"
Name: "{group}\Restore my previous setup"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\restore.ps1"""; WorkingDir: "{app}"
Name: "{group}\Backups and logs"; Filename: "{localappdata}\NishantDSASetup"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\setup.ps1"" {code:SetupArgs}"; StatusMsg: "Setting up... follow the PowerShell window."; Flags: waituntilterminated

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\restore.ps1"" -FromUninstaller"; RunOnceId: "RestorePreviousSetup"; Flags: waituntilterminated

[Code]
function SetupArgs(Param: String): String;
begin
  if WizardSilent then
    Result := '-Unattended'
  else
    Result := '';
end;
