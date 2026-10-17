# Nishant's DSA Setup for Windows.
# Installs and configures VS Code, a modern g++, fonts, the terminal prompt and
# CPH Plus. Everything it changes is recorded so restore.ps1 can undo it.
param([switch]$Unattended)

. (Join-Path $PSScriptRoot 'common.ps1')
$script:Unattended = [bool]$Unattended
Write-Log "=== setup.ps1 starting (unattended=$Unattended, PowerShell $($PSVersionTable.PSVersion)) ==="
# Any unexpected error ends up in the log with its line number instead of
# closing the window silently.
trap {
    Write-Log "FATAL $_ $($_.InvocationInfo.PositionMessage)"
    Write-Host ''
    Write-Host "  Something went wrong: $_" -ForegroundColor Red
    Write-Host "  Details are in $LogPath. Running the setup again usually fixes download problems."
    if (-not $script:Unattended) { try { Read-Host '  Press Enter to close' | Out-Null } catch {} }
    exit 2
}
$Payload = Join-Path (Split-Path $PSScriptRoot -Parent) 'payload'
$Versions = Get-Content -Raw (Join-Path $Payload 'config\versions.json') | ConvertFrom-Json

function Invoke-Native([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $exe @arguments 2>&1 | ForEach-Object { "$_" }
        return @{ code = $LASTEXITCODE; out = ($out -join "`n") }
    } catch {
        return @{ code = 1; out = "$_" }
    } finally {
        $ErrorActionPreference = $old
    }
}

function Quote-Single([string]$s) { return "'" + $s.Replace("'", "''") + "'" }

# ------------------------------------------------------------------ intro

try { Clear-Host } catch {}
Write-Host ''
Write-Host '  =============================================' -ForegroundColor Magenta
Write-Host "        $AppName (Windows)" -ForegroundColor Magenta
Write-Host '  =============================================' -ForegroundColor Magenta
Write-Host ''
Write-Host '  This will set up a complete C++ / DSA environment:'
Write-Host '    - Visual Studio Code (if missing)'
Write-Host "    - GCC $($Versions.winlibsVersion) g++ compiler (if you do not already have a modern one)"
Write-Host '    - Fonts: MesloLGM Nerd Font, Hack, Fira Code'
Write-Host '    - Powerline terminal prompt (oh-my-posh) for PowerShell'
Write-Host '    - VS Code extensions: C/C++, Code Runner, Auto Hide, CPH Plus'
Write-Host '    - Editor theme, fonts and C++ snippets (cpts / cpnts)'
Write-Host ''
Write-Host '  Nothing you already have is deleted. Every file is backed up first and'
Write-Host '  you can undo everything later with "Restore my previous setup".'
Write-Host ''

$manifest = Get-Manifest
if ($manifest) {
    Write-Host '  This setup has been run on this PC before. Running it again updates' -ForegroundColor Yellow
    Write-Host '  everything; your original settings are still saved for restore.' -ForegroundColor Yellow
    Write-Host ''
} else {
    $manifest = New-Manifest
}

if (-not (Read-YesNo 'Start the setup?' $true)) { Write-Host '  Cancelled. Nothing was changed.'; exit 0 }
Write-Log "=== setup started (unattended=$Unattended) ==="

$CodeUserDir = Join-Path $env:APPDATA 'Code\User'
$SettingsPath = Join-Path $CodeUserDir 'settings.json'
$SnippetsPath = Join-Path $CodeUserDir 'snippets\nishant-dsa.code-snippets'
$Docs = [Environment]::GetFolderPath('MyDocuments')
$ProfilePaths = @(Join-Path $Docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
if ((Get-Command pwsh -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $Docs 'PowerShell'))) {
    $ProfilePaths += Join-Path $Docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
}
$WtSettings = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ }

$failures = @()

# ------------------------------------------------------------------ 1. backup

Write-Step '[1/8] Backing up your current settings'
$backup = Backup-Files $manifest (@($SettingsPath, (Join-Path $CodeUserDir 'keybindings.json')) + $ProfilePaths + $WtSettings)
Write-Ok "Backup saved to $backup"

# ------------------------------------------------------------------ 2. VS Code

Write-Step '[2/8] Visual Studio Code'
function Find-VSCode {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
    )
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd' }
    $onPath = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($onPath) { $candidates = @($onPath.Source) + $candidates }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}
$Code = Find-VSCode
if ($Code) {
    Write-Skip "already installed ($Code)"
} else {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64-user' } else { 'win32-x64-user' }
    $installer = Join-Path $env:TEMP 'NishantDSA-VSCodeSetup.exe'
    Write-Info 'Downloading VS Code...'
    try {
        Get-File "https://update.code.visualstudio.com/latest/$arch/stable" $installer
        Write-Info 'Installing VS Code (this takes a minute)...'
        $p = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath' -PassThru -Wait
        Remove-Item -Force $installer -ErrorAction SilentlyContinue
        $Code = Find-VSCode
        if ($Code) {
            $manifest.installed.vscode = $true; Save-Manifest $manifest
            Write-Ok 'VS Code installed'
        } else {
            throw "installer exit code $($p.ExitCode)"
        }
    } catch {
        Write-Fail "Could not install VS Code: $_"
        Write-Info 'Install it from https://code.visualstudio.com and run this setup again.'
        $failures += 'VS Code'
    }
}

# ------------------------------------------------------------------ 3. compiler

Write-Step '[3/8] C++ compiler (g++)'
$TestSource = @'
#include <bits/stdc++.h>
using namespace std;
int main() { vector<int> v{3, 1, 2}; sort(v.begin(), v.end()); cout << v[0] << v[1] << v[2]; }
'@

function Test-Gpp([string]$gpp) {
    $r = Invoke-Native $gpp @('-dumpfullversion', '-dumpversion')
    if ($r.code -ne 0) { return @{ ok = $false; version = '?'; major = 0 } }
    $version = ($r.out -split "`n")[0].Trim()
    $major = 0; [void][int]::TryParse(($version -split '\.')[0], [ref]$major)
    $dir = Join-Path $env:TEMP ('nishantdsa-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    try {
        Set-Content -Path (Join-Path $dir 't.cpp') -Value $TestSource -Encoding ASCII
        $exe = Join-Path $dir 't.exe'
        $c = Invoke-Native $gpp @((Join-Path $dir 't.cpp'), '-static', '-o', $exe)
        if ($c.code -ne 0 -or -not (Test-Path $exe)) { return @{ ok = $false; version = $version; major = $major } }
        # The compiler's own DLLs must be found when the program runs.
        $oldPath = $env:PATH
        $env:PATH = (Split-Path $gpp) + ';' + $env:PATH
        try { $run = Invoke-Native $exe @() } finally { $env:PATH = $oldPath }
        return @{ ok = ($run.out.Trim() -eq '123'); version = $version; major = $major }
    } finally {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
}

$OurGpp = Join-Path $CompilerDir 'bin\g++.exe'
$Gpp = $null
$candidates = @()
if (Test-Path $OurGpp) { $candidates += $OurGpp }
$candidates += @(Get-Command g++.exe -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
foreach ($cand in ($candidates | Select-Object -Unique)) {
    $t = Test-Gpp $cand
    if ($t.ok -and $t.major -ge $Versions.minGccMajor) {
        $Gpp = $cand
        Write-Skip "using g++ $($t.version) ($cand)"
        break
    } elseif ($t.major -gt 0) {
        Write-Info "found g++ $($t.version) at $cand - too old or not working, it will be left as it is"
    }
}
if (-not $Gpp) {
    $zip = Join-Path $env:TEMP 'NishantDSA-winlibs.zip'
    try {
        Write-Info "Downloading GCC $($Versions.winlibsVersion) (about 270 MB, please wait)..."
        Get-File $Versions.winlibsUrl $zip
        Write-Info 'Extracting (this can take a few minutes)...'
        if (Test-Path $CompilerDir) { Remove-Item -Recurse -Force $CompilerDir }
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        $extracted = $false
        if ($tar) {
            $r = Invoke-Native $tar.Source @('-xf', $zip, '-C', $Root)
            $extracted = ($r.code -eq 0 -and (Test-Path $OurGpp))
        }
        if (-not $extracted) { Expand-Archive -Path $zip -DestinationPath $Root -Force }
        Remove-Item -Force $zip -ErrorAction SilentlyContinue
        $t = Test-Gpp $OurGpp
        if (-not $t.ok) { throw 'the new compiler did not pass the test program' }
        $Gpp = $OurGpp
        $manifest.installed.compiler = $true; Save-Manifest $manifest
        Write-Ok "g++ $($t.version) installed to $CompilerDir"
    } catch {
        Write-Fail "Could not install GCC: $_"
        $failures += 'g++ compiler'
    }
}
$GccDir = if ($Gpp) { Split-Path $Gpp } else { $null }

# ------------------------------------------------------------------ 4. fonts

Write-Step '[4/8] Fonts'
$userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force -Path $userFontDir | Out-Null
if (-not (Test-Path $UserFontKey)) { New-Item -Path $UserFontKey -Force | Out-Null }
$newFonts = 0
foreach ($font in Get-ChildItem (Join-Path $Payload 'fonts\*.ttf')) {
    if (Test-FontInstalled $font.Name) { continue }
    try {
        $dest = Join-Path $userFontDir $font.Name
        Copy-Item -Force $font.FullName $dest
        $reg = $FontRegNames[$font.Name]
        New-ItemProperty -Path $UserFontKey -Name $reg -Value $dest -PropertyType String -Force | Out-Null
        [void][NishantDsa.FontApi]::AddFontResourceW($dest)
        Add-ToList $manifest 'fonts' ([pscustomobject]@{ file = $dest; regName = $reg })
        $newFonts++
    } catch {
        Write-Warn2 "could not install $($font.Name): $_"
    }
}
Save-Manifest $manifest
if ($newFonts -gt 0) { Send-FontChange; Write-Ok "$newFonts font files installed" } else { Write-Skip 'all fonts already installed' }

# ------------------------------------------------------------------ 5. terminal prompt

Write-Step '[5/8] Terminal prompt (oh-my-posh)'
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$Omp = Join-Path $BinDir 'oh-my-posh.exe'
$wantVersion = $Versions.ohMyPoshVersion.TrimStart('v')
$haveVersion = if (Test-Path $Omp) { (Invoke-Native $Omp @('version')).out.Trim() } else { '' }
if ($haveVersion -eq $wantVersion) {
    Write-Skip "oh-my-posh $haveVersion already installed"
} else {
    $asset = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'posh-windows-arm64.exe' } else { 'posh-windows-amd64.exe' }
    try {
        Get-File "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$($Versions.ohMyPoshVersion)/$asset" $Omp
        $manifest.installed.ohMyPosh = $true; Save-Manifest $manifest
        Write-Ok "oh-my-posh $wantVersion installed"
    } catch {
        Write-Fail "Could not download oh-my-posh: $_"
        $failures += 'oh-my-posh'
    }
}
Copy-Item -Force (Join-Path $Payload 'config\nishant.omp.json') $ThemePath

# Profiles only run if scripts are allowed. RemoteSigned is the usual setting
# for developers and only applies to this Windows user.
$policies = Get-ExecutionPolicy -List
$gpo = $policies | Where-Object { $_.Scope -in @('MachinePolicy', 'UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' }
$effective = Get-ExecutionPolicy
if ($effective -in @('Restricted', 'AllSigned', 'Undefined')) {
    if ($gpo) {
        Write-Warn2 "Your organisation sets the PowerShell script policy ($effective), so the prompt theme may not load."
    } else {
        $previous = ($policies | Where-Object { $_.Scope -eq 'CurrentUser' }).ExecutionPolicy.ToString()
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            if (-not $manifest.executionPolicy) {
                $manifest.executionPolicy = [pscustomobject]@{ previous = $previous; applied = 'RemoteSigned' }
                Save-Manifest $manifest
            }
            Write-Ok 'Allowed PowerShell profile scripts for your user (RemoteSigned)'
        } catch {
            Write-Warn2 "Could not change the PowerShell script policy: $_"
        }
    }
}

$block = @(
    $BlockStart,
    "if (Test-Path $(Quote-Single $Omp)) { & $(Quote-Single $Omp) init pwsh --config $(Quote-Single $ThemePath) | Invoke-Expression }",
    $BlockEnd
) -join "`r`n"
foreach ($profilePath in $ProfilePaths) {
    $existed = Test-Path $profilePath
    $content = if ($existed) { [IO.File]::ReadAllText($profilePath) } else { '' }
    if ($content.Contains($BlockStart)) {
        Write-Skip "prompt already enabled in $profilePath"
        continue
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
    $prefix = if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { "`r`n" } else { '' }
    [IO.File]::AppendAllText($profilePath, $prefix + "`r`n" + $block + "`r`n", (New-Object Text.UTF8Encoding($false)))
    if (-not (@($manifest.profiles) | Where-Object { $_.path -eq $profilePath })) {
        Add-ToList $manifest 'profiles' ([pscustomobject]@{ path = $profilePath; createdFile = (-not $existed) })
        Save-Manifest $manifest
    }
    Write-Ok "prompt enabled in $profilePath"
}

# ------------------------------------------------------------------ 6. Windows Terminal

Write-Step '[6/8] Windows Terminal font'
if (@($WtSettings).Count -eq 0) {
    Write-Skip 'Windows Terminal settings not found (open Windows Terminal once, then run setup again to style it)'
}
foreach ($wt in $WtSettings) {
    if (Set-TrackedJson $manifest $wt @(@{ path = @('profiles', 'defaults', 'font', 'face'); value = 'MesloLGM Nerd Font' }) 'Windows Terminal settings') {
        Write-Ok "font set in $wt"
    }
}

# ------------------------------------------------------------------ 7. extensions

Write-Step '[7/8] VS Code extensions'
if (-not $Code) {
    Write-Skip 'VS Code is not available'
} else {
    $installedExt = @((Invoke-Native $Code @('--list-extensions')).out -split "`n" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    foreach ($ext in $Versions.conflictingExtensions) {
        if ($installedExt -contains $ext.ToLower()) {
            $r = Invoke-Native $Code @('--uninstall-extension', $ext)
            if ($r.code -eq 0) {
                if (@($manifest.extensionsRemoved) -notcontains $ext) { Add-ToList $manifest 'extensionsRemoved' $ext; Save-Manifest $manifest }
                Write-Ok "removed $ext (replaced by CPH Plus; your CPH settings still work)"
            } else {
                Write-Warn2 "could not remove $ext"
            }
        }
    }
    foreach ($ext in $Versions.extensions) {
        if ($installedExt -contains $ext.ToLower()) { Write-Skip "$ext already installed"; continue }
        $r = Invoke-Native $Code @('--install-extension', $ext)
        if ($r.code -eq 0) {
            Add-ToList $manifest 'extensionsAdded' $ext; Save-Manifest $manifest
            Write-Ok "installed $ext"
        } else {
            Write-Fail "could not install $ext"
            $failures += $ext
        }
    }
    $hadCph = $installedExt -contains 'nishant.cph-plus'
    $r = Invoke-Native $Code @('--install-extension', (Join-Path $Payload 'extensions\cph-plus.vsix'), '--force')
    if ($r.code -eq 0) {
        if (-not $hadCph -and @($manifest.extensionsAdded) -notcontains 'nishant.cph-plus') {
            Add-ToList $manifest 'extensionsAdded' 'nishant.cph-plus'; Save-Manifest $manifest
        }
        Write-Ok 'installed CPH Plus'
    } else {
        Write-Fail 'could not install CPH Plus'
        $failures += 'CPH Plus'
    }
}

# ------------------------------------------------------------------ 8. settings

Write-Step '[8/8] Editor settings and snippets'
$current = Read-JsoncFile $SettingsPath
$changes = @()
$shared = Get-Content -Raw (Join-Path $Payload 'config\vscode-settings.json') | ConvertFrom-Json
foreach ($p in $shared.PSObject.Properties) { $changes += @{ path = @($p.Name); value = $p.Value } }
$changes += @{ path = @('terminal.integrated.defaultProfile.windows'); value = 'PowerShell' }
if ($Gpp -and $current.ok) {
    $Gcc = Join-Path $GccDir 'gcc.exe'
    $changes += @{ path = @('C_Cpp.default.compilerPath'); value = $Gpp }
    $changes += @{ path = @('cph.language.cpp.Command'); value = $Gpp }
    # Static linking makes each program self-contained, so it never loads the
    # runtime DLLs of an older MinGW that may be earlier on PATH.
    $cppArgs = Get-PathValue $current.obj @('cph.language.cpp.Args')
    $argText = if ($cppArgs.found) { "$($cppArgs.value)".Trim() } else { '' }
    if (($argText -split '\s+') -notcontains '-static') {
        $changes += @{ path = @('cph.language.cpp.Args'); value = ($argText + ' -static').Trim() }
    }
    if (Test-Path $Gcc) { $changes += @{ path = @('cph.language.c.Command'); value = $Gcc } }

    # Merge into the student's existing maps instead of replacing them.
    $map = (Get-PathValue $current.obj @('code-runner.executorMap'))
    $executorMap = if ($map.found -and $map.value -is [pscustomobject]) { $map.value | ConvertTo-Json -Depth 20 | ConvertFrom-Json } else { [pscustomobject]@{} }
    $cppCmd = 'cd $dir ; if ($?) { & ' + (Quote-Single $Gpp) + ' $fileName -static -o $fileNameWithoutExt } ; if ($?) { .\$fileNameWithoutExt }'
    $cCmd = 'cd $dir ; if ($?) { & ' + (Quote-Single $Gcc) + ' $fileName -static -o $fileNameWithoutExt } ; if ($?) { .\$fileNameWithoutExt }'
    [void](Set-PathValue $executorMap @('cpp') $cppCmd)
    if (Test-Path $Gcc) { [void](Set-PathValue $executorMap @('c') $cCmd) }
    $changes += @{ path = @('code-runner.executorMap'); value = $executorMap }

    $envMap = (Get-PathValue $current.obj @('terminal.integrated.env.windows'))
    $termEnv = if ($envMap.found -and $envMap.value -is [pscustomobject]) { $envMap.value | ConvertTo-Json -Depth 20 | ConvertFrom-Json } else { [pscustomobject]@{} }
    $termPath = Get-PathValue $termEnv @('PATH')
    if (-not ($termPath.found -and "$($termPath.value)".StartsWith($GccDir))) {
        [void](Set-PathValue $termEnv @('PATH') ($GccDir + ';${env:PATH}'))
        $changes += @{ path = @('terminal.integrated.env.windows'); value = $termEnv }
    }
}
if (Set-TrackedJson $manifest $SettingsPath $changes 'VS Code settings') {
    Write-Ok 'VS Code settings updated'
} else {
    $failures += 'VS Code settings'
}

$snippetSource = Join-Path $Payload 'config\nishant-dsa.code-snippets'
if (-not (Test-Path $SnippetsPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SnippetsPath) | Out-Null
    Copy-Item $snippetSource $SnippetsPath
    if (@($manifest.createdFiles) -notcontains $SnippetsPath) { Add-ToList $manifest 'createdFiles' $SnippetsPath; Save-Manifest $manifest }
    Write-Ok 'C++ snippets added (type cpts or cpnts in a .cpp file)'
} elseif (@($manifest.createdFiles) -contains $SnippetsPath) {
    Copy-Item -Force $snippetSource $SnippetsPath
    Write-Skip 'C++ snippets already added (updated)'
} else {
    Write-Skip 'a snippets file with the same name already exists; left it alone'
}

# ------------------------------------------------------------------ done

Write-Host ''
if ($Gpp) {
    $t = Test-Gpp $Gpp
    if ($t.ok) { Write-Ok "Test program compiled and ran with g++ $($t.version)" } else { Write-Fail 'Test program failed to compile' }
}
Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host '  All done!' -ForegroundColor Green
} else {
    Write-Host "  Finished with problems in: $($failures -join ', ')" -ForegroundColor Yellow
    Write-Host '  Check your internet connection and run the setup again; finished steps are skipped.'
}
Write-Host ''
Write-Host '  Next steps:'
Write-Host '    1. Close ALL VS Code and terminal windows, then open VS Code again.'
Write-Host '    2. Open a folder, create a .cpp file, type cpts and press Tab.'
Write-Host '    3. Use the CPH panel (Ctrl+Alt+B runs test cases).'
Write-Host ''
Write-Host "  To undo everything: Start menu -> $AppName -> Restore my previous setup"
Write-Host "  Log file: $LogPath"
Write-Log "=== setup finished, failures: $($failures -join ', ') ==="

if (-not $Unattended) {
    if ($Code -and (Read-YesNo 'Open VS Code now?' $true)) { Start-Process -FilePath $Code -WindowStyle Hidden }
    Read-Host '  Press Enter to close' | Out-Null
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
