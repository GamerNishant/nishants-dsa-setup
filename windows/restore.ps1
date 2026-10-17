# Restores the setup that existed before Nishant's DSA Setup ran.
# Only undoes what setup.ps1 recorded in the manifest. Settings the student
# changed after setup are kept. Backups are never deleted.
param([switch]$Unattended, [switch]$FromUninstaller)

. (Join-Path $PSScriptRoot 'common.ps1')
$script:Unattended = [bool]$Unattended

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

function Wait-Close { if (-not $script:Unattended) { Read-Host '  Press Enter to close' | Out-Null } }

Write-Host ''
Write-Host '  =============================================' -ForegroundColor Magenta
Write-Host "     $AppName - Restore previous setup" -ForegroundColor Magenta
Write-Host '  =============================================' -ForegroundColor Magenta
Write-Host ''

$manifest = Get-Manifest
if (-not $manifest) {
    Write-Host '  Nothing to restore: the setup has not changed anything on this PC.'
    Wait-Close
    exit 0
}

Write-Host '  This puts back the settings you had before running the setup:'
Write-Host '    - VS Code settings, Windows Terminal font and PowerShell profile'
Write-Host '    - removes the extensions, fonts and prompt the setup added'
Write-Host '    - reinstalls any extension the setup replaced'
Write-Host '  Settings you changed yourself after the setup are kept.'
Write-Host ''
if (-not (Read-YesNo 'Restore your previous setup?' $true)) { Write-Host '  Cancelled. Nothing was changed.'; Wait-Close; exit 0 }
Write-Log '=== restore started ==='

# Safety copy of the current state before restoring, in case the student wants it back.
$files = @($manifest.jsonEdits | ForEach-Object { $_.file }) + @($manifest.profiles | ForEach-Object { $_.path }) | Where-Object { $_ } | Select-Object -Unique
$before = Backup-Files $manifest $files
Write-Info "Current settings saved to $before before restoring"

# ------------------------------------------------------------------ settings files
Write-Step 'Settings'
foreach ($file in (@($manifest.jsonEdits | ForEach-Object { $_.file }) | Select-Object -Unique)) {
    $label = if ($file -like '*Terminal*') { 'Windows Terminal settings' } else { 'VS Code settings' }
    Restore-TrackedJson $manifest $file $label
}
foreach ($f in @($manifest.createdFiles)) {
    if ($f -and (Test-Path $f)) { Remove-Item -Force $f; Write-Ok "removed $f" }
}

# ------------------------------------------------------------------ profiles
Write-Step 'PowerShell profile'
foreach ($p in @($manifest.profiles)) {
    if (-not $p -or -not (Test-Path $p.path)) { continue }
    $text = [IO.File]::ReadAllText($p.path)
    $pattern = '(\r?\n)?' + [regex]::Escape($BlockStart) + '[\s\S]*?' + [regex]::Escape($BlockEnd) + '\r?\n?'
    $newText = [regex]::Replace($text, $pattern, '')
    if ($newText -ne $text) {
        if ($p.createdFile -and $newText.Trim() -eq '') {
            Remove-Item -Force $p.path
            Write-Ok "removed $($p.path) (it was created by the setup)"
        } else {
            [IO.File]::WriteAllText($p.path, $newText, (New-Object Text.UTF8Encoding($false)))
            Write-Ok "prompt removed from $($p.path)"
        }
    }
}
if ($manifest.executionPolicy) {
    $now = (Get-ExecutionPolicy -Scope CurrentUser).ToString()
    if ($now -eq $manifest.executionPolicy.applied) {
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $manifest.executionPolicy.previous -Force
            Write-Ok "PowerShell script policy set back to $($manifest.executionPolicy.previous)"
        } catch { Write-Warn2 "could not reset the PowerShell script policy: $_" }
    }
}

# ------------------------------------------------------------------ extensions
Write-Step 'VS Code extensions'
$code = $null
foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'), (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'))) {
    if (Test-Path $c) { $code = $c; break }
}
if (-not $code) { $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue; if ($cmd) { $code = $cmd.Source } }
if ($code) {
    foreach ($ext in @($manifest.extensionsAdded)) {
        if (-not $ext) { continue }
        $r = Invoke-Native $code @('--uninstall-extension', $ext)
        if ($r.code -eq 0) { Write-Ok "removed $ext" } else { Write-Skip "$ext was already removed" }
    }
    foreach ($ext in @($manifest.extensionsRemoved)) {
        if (-not $ext) { continue }
        $r = Invoke-Native $code @('--install-extension', $ext)
        if ($r.code -eq 0) { Write-Ok "reinstalled $ext" } else { Write-Warn2 "could not reinstall $ext (install it again from the Extensions view)" }
    }
} else {
    Write-Skip 'VS Code not found'
}

# ------------------------------------------------------------------ fonts
Write-Step 'Fonts'
$removed = 0
foreach ($font in @($manifest.fonts)) {
    if (-not $font) { continue }
    try {
        [void][NishantDsa.FontApi]::RemoveFontResourceW($font.file)
        Remove-ItemProperty -Path $UserFontKey -Name $font.regName -ErrorAction SilentlyContinue
        if (Test-Path $font.file) { Remove-Item -Force $font.file -ErrorAction Stop }
        $removed++
    } catch {
        Write-Warn2 "$(Split-Path $font.file -Leaf) is in use; it will stop loading after you sign out"
    }
}
if ($removed -gt 0) { Send-FontChange; Write-Ok "$removed font files removed" } else { Write-Skip 'no fonts to remove' }

# ------------------------------------------------------------------ tools
Write-Step 'Tools'
if ($manifest.installed.ohMyPosh -or (Test-Path $BinDir)) {
    Remove-Item -Recurse -Force $BinDir -ErrorAction SilentlyContinue
    Remove-Item -Force $ThemePath -ErrorAction SilentlyContinue
    Write-Ok 'removed the prompt tool (oh-my-posh)'
}
if ($manifest.installed.compiler -and (Test-Path $CompilerDir)) {
    if (Read-YesNo "Remove the g++ compiler the setup installed ($CompilerDir)?" $true) {
        Remove-Item -Recurse -Force $CompilerDir
        Write-Ok 'removed the g++ compiler'
    } else {
        Write-Skip "kept the compiler at $CompilerDir"
    }
}
if ($manifest.installed.vscode) {
    $uninstaller = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\unins000.exe'
    if ((Test-Path $uninstaller) -and (Read-YesNo 'VS Code was installed by the setup. Uninstall VS Code too?' $false)) {
        Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/NORESTART' -Wait
        Write-Ok 'VS Code uninstalled'
    } else {
        Write-Skip 'kept VS Code'
    }
}

# ------------------------------------------------------------------ done
$doneDir = Join-Path $StateDir ('restored-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $doneDir | Out-Null
Move-Item -Force $ManifestPath (Join-Path $doneDir 'manifest.json')
Write-Log '=== restore finished ==='
Write-Host ''
Write-Host '  Your previous setup has been restored.' -ForegroundColor Green
Write-Host "  All backups are kept in $StateDir\backups"
Write-Host '  Close and reopen VS Code and your terminals to see the change.'
Write-Host ''
Wait-Close
exit 0
