# Shared helpers for setup.ps1 and restore.ps1 (Nishant's DSA Setup, Windows).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# PowerShell 5.1 wraps arrays as {value, Count} in ConvertTo-Json without this.
Remove-TypeData System.Array -ErrorAction SilentlyContinue
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$script:AppName = "Nishant's DSA Setup"
$script:Root = Join-Path $env:LOCALAPPDATA 'NishantDSASetup'
$script:StateDir = Join-Path $script:Root 'state'
$script:ManifestPath = Join-Path $script:StateDir 'manifest.json'
$script:BinDir = Join-Path $script:Root 'bin'
$script:CompilerDir = Join-Path $script:Root 'mingw64'
$script:ThemePath = Join-Path $script:Root 'nishant.omp.json'
$script:LogPath = Join-Path $script:Root 'setup.log'
$script:Unattended = $false
$script:BlockStart = "# >>> Nishant's DSA Setup >>>"
$script:BlockEnd = "# <<< Nishant's DSA Setup <<<"

New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null

function Write-Log([string]$text) {
    try { Add-Content -Path $script:LogPath -Value ("{0}  {1}" -f (Get-Date -Format s), $text) } catch {}
}
function Write-Step([string]$text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan; Write-Log "STEP $text" }
function Write-Ok([string]$text) { Write-Host "    [ok]   $text" -ForegroundColor Green; Write-Log "OK $text" }
function Write-Skip([string]$text) { Write-Host "    [skip] $text" -ForegroundColor DarkGray; Write-Log "SKIP $text" }
function Write-Info([string]$text) { Write-Host "    $text"; Write-Log "INFO $text" }
function Write-Warn2([string]$text) { Write-Host "    [warn] $text" -ForegroundColor Yellow; Write-Log "WARN $text" }
function Write-Fail([string]$text) { Write-Host "    [fail] $text" -ForegroundColor Red; Write-Log "FAIL $text" }

function Read-YesNo([string]$question, [bool]$default) {
    if ($script:Unattended) { return $default }
    $hint = if ($default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "    $question $hint").Trim().ToLower()
        if ($answer -eq '') { return $default }
        if ($answer -in @('y', 'yes')) { return $true }
        if ($answer -in @('n', 'no')) { return $false }
    }
}

# ---------------------------------------------------------------- manifest

function New-Manifest {
    [pscustomobject]@{
        version          = 1
        createdAt        = (Get-Date -Format s)
        backupDirs       = @()
        jsonEdits        = @()   # { file, createdFile, path[], hadValue, previous, applied }
        createdFiles     = @()   # files we created outright (snippets, theme)
        profiles         = @()   # { path, createdFile }
        executionPolicy  = $null # { previous, applied }
        installed        = [pscustomobject]@{ vscode = $false; compiler = $false; ohMyPosh = $false }
        fonts            = @()   # { file, regName }
        extensionsAdded  = @()
        extensionsRemoved = @()
    }
}

function Get-Manifest {
    if (Test-Path $script:ManifestPath) {
        return (Get-Content -Raw -Path $script:ManifestPath | ConvertFrom-Json)
    }
    return $null
}

function Save-Manifest($manifest) {
    $json = ConvertTo-Json -InputObject $manifest -Depth 50
    [IO.File]::WriteAllText($script:ManifestPath, $json, (New-Object Text.UTF8Encoding($false)))
}

function Add-ToList($manifest, [string]$name, $item) {
    $manifest.$name = @(@($manifest.$name) | Where-Object { $null -ne $_ }) + , $item
}

# ---------------------------------------------------------------- JSON with comments

# VS Code and Windows Terminal settings are JSONC: comments and trailing commas.
# Both passes track string literals so "//" inside a value (e.g. a URL) is kept.
function Remove-JsonComments([string]$text) {
    $sb = New-Object Text.StringBuilder
    $inString = $false; $escape = $false
    $i = 0; $n = $text.Length
    while ($i -lt $n) {
        $c = $text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($escape) { $escape = $false }
            elseif ($c -eq '\') { $escape = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++; continue
        }
        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $n -and $text[$i + 1] -eq '/') {
            while ($i -lt $n -and $text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '/' -and $i + 1 -lt $n -and $text[$i + 1] -eq '*') {
            $i += 2
            while ($i + 1 -lt $n -and -not ($text[$i] -eq '*' -and $text[$i + 1] -eq '/')) { $i++ }
            $i += 2; continue
        }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}

function Remove-TrailingCommas([string]$text) {
    $sb = New-Object Text.StringBuilder
    $inString = $false; $escape = $false
    $n = $text.Length
    for ($i = 0; $i -lt $n; $i++) {
        $c = $text[$i]
        if ($inString) {
            if ($escape) { $escape = $false }
            elseif ($c -eq '\') { $escape = $true }
            elseif ($c -eq '"') { $inString = $false }
        } elseif ($c -eq '"') {
            $inString = $true
        } elseif ($c -eq ',') {
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($text[$j])) { $j++ }
            if ($j -lt $n -and ($text[$j] -eq '}' -or $text[$j] -eq ']')) { continue }
        }
        [void]$sb.Append($c)
    }
    return $sb.ToString()
}

function ConvertFrom-Jsonc([string]$text) {
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $clean = (Remove-TrailingCommas (Remove-JsonComments $text)).Trim()
    if ($clean -eq '') { return [pscustomobject]@{} }
    return ($clean | ConvertFrom-Json)
}

# Returns @{ ok; obj; exists }. ok=false means the file exists but could not be parsed.
function Read-JsoncFile([string]$path) {
    if (-not (Test-Path $path)) { return @{ ok = $true; exists = $false; obj = [pscustomobject]@{} } }
    try {
        $text = [IO.File]::ReadAllText($path)
        $obj = ConvertFrom-Jsonc $text
        if ($obj -isnot [pscustomobject]) { return @{ ok = $false; exists = $true; obj = $null } }
        return @{ ok = $true; exists = $true; obj = $obj }
    } catch {
        return @{ ok = $false; exists = $true; obj = $null }
    }
}

# Re-indents JSON with 4 spaces, like VS Code writes it (PowerShell 5.1 output
# is valid but oddly indented).
function Format-Json([string]$json) {
    $sb = New-Object Text.StringBuilder
    $indent = 0; $inString = $false; $escape = $false
    $nl = { param($level) [void]$sb.Append("`n"); [void]$sb.Append(' ' * (4 * $level)) }
    for ($i = 0; $i -lt $json.Length; $i++) {
        $c = $json[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($escape) { $escape = $false } elseif ($c -eq '\') { $escape = $true } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        switch ($c) {
            '"' { $inString = $true; [void]$sb.Append($c) }
            { $_ -eq '{' -or $_ -eq '[' } {
                # Keep empty {} and [] on one line.
                $j = $i + 1; while ($j -lt $json.Length -and [char]::IsWhiteSpace($json[$j])) { $j++ }
                $close = if ($c -eq '{') { '}' } else { ']' }
                if ($j -lt $json.Length -and $json[$j] -eq $close) { [void]$sb.Append($c + $close); $i = $j }
                else { [void]$sb.Append($c); $indent++; & $nl $indent }
            }
            { $_ -eq '}' -or $_ -eq ']' } { $indent--; & $nl $indent; [void]$sb.Append($c) }
            ',' { [void]$sb.Append(','); & $nl $indent }
            ':' { [void]$sb.Append(': ') }
            default { if (-not [char]::IsWhiteSpace($c)) { [void]$sb.Append($c) } }
        }
    }
    return $sb.ToString()
}

function Write-JsonFile([string]$path, $obj) {
    $json = Format-Json (ConvertTo-Json -InputObject $obj -Depth 50)
    # PowerShell 5.1 escapes these needlessly; they are valid unescaped in JSON.
    # Built from char codes so the escape sequences survive any re-encoding of this file.
    $u = [string][char]92 + 'u00'
    $json = $json.Replace($u + '27', [string][char]39).Replace($u + '3c', '<').Replace($u + '3e', '>').Replace($u + '26', '&')
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-Canonical($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) { return (ConvertTo-Json -InputObject $v -Compress) }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or $v -is [single]) {
        return ([double]$v).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if ($v -is [Collections.IDictionary]) {
        $parts = foreach ($k in ($v.Keys | Sort-Object)) { (ConvertTo-Json -InputObject ([string]$k) -Compress) + ':' + (Get-Canonical $v[$k]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($v -is [pscustomobject]) {
        $parts = foreach ($p in ($v.PSObject.Properties | Sort-Object Name)) { (ConvertTo-Json -InputObject $p.Name -Compress) + ':' + (Get-Canonical $p.Value) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($v -is [Collections.IEnumerable]) {
        $parts = foreach ($x in $v) { Get-Canonical $x }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-Json -InputObject $v -Compress)
}

function Test-JsonEqual($a, $b) { return (Get-Canonical $a) -eq (Get-Canonical $b) }

function Get-PathValue($obj, [string[]]$path) {
    $cur = $obj
    foreach ($seg in $path) {
        if ($cur -isnot [pscustomobject]) { return @{ found = $false } }
        $prop = $cur.PSObject.Properties[$seg]
        if ($null -eq $prop) { return @{ found = $false } }
        $cur = $prop.Value
    }
    return @{ found = $true; value = $cur }
}

# Returns $false if an intermediate segment exists but is not an object.
function Set-PathValue($obj, [string[]]$path, $value) {
    $cur = $obj
    for ($i = 0; $i -lt $path.Length - 1; $i++) {
        $seg = $path[$i]
        $prop = $cur.PSObject.Properties[$seg]
        if ($null -eq $prop) {
            $child = [pscustomobject]@{}
            $cur | Add-Member -NotePropertyName $seg -NotePropertyValue $child
            $cur = $child
        } elseif ($prop.Value -is [pscustomobject]) {
            $cur = $prop.Value
        } else {
            return $false
        }
    }
    $leaf = $path[$path.Length - 1]
    if ($cur.PSObject.Properties[$leaf]) { $cur.$leaf = $value }
    else { $cur | Add-Member -NotePropertyName $leaf -NotePropertyValue $value }
    return $true
}

function Remove-PathValue($obj, [string[]]$path) {
    $cur = $obj
    for ($i = 0; $i -lt $path.Length - 1; $i++) {
        $prop = $cur.PSObject.Properties[$path[$i]]
        if ($null -eq $prop -or $prop.Value -isnot [pscustomobject]) { return }
        $cur = $prop.Value
    }
    $cur.PSObject.Properties.Remove($path[$path.Length - 1])
}

# Sets each { path; value } in a JSONC file, recording what was there before.
# Re-runs keep the very first "previous" value so restore goes back to the
# student's own setting, not to an earlier run of this tool.
function Set-TrackedJson($manifest, [string]$file, [object[]]$changes, [string]$label) {
    $read = Read-JsoncFile $file
    if (-not $read.ok) {
        Write-Warn2 "$label could not be read (it may contain a syntax error). Left it untouched: $file"
        return $false
    }
    $obj = $read.obj
    $changed = 0
    foreach ($change in $changes) {
        $path = [string[]]$change.path
        $existing = @($manifest.jsonEdits | Where-Object { $_.file -eq $file -and ((@($_.path) -join "`0") -eq ($path -join "`0")) })
        $current = Get-PathValue $obj $path
        if ($current.found -and (Test-JsonEqual $current.value $change.value)) {
            if ($existing.Count -eq 0) { continue } # student already had exactly this
        }
        if (-not (Set-PathValue $obj $path $change.value)) {
            Write-Warn2 "$label`: could not set $($path -join '.') (unexpected structure), skipped"
            continue
        }
        if ($existing.Count -gt 0) {
            $existing[0].applied = $change.value
        } else {
            Add-ToList $manifest 'jsonEdits' ([pscustomobject]@{
                file        = $file
                createdFile = (-not $read.exists)
                path        = $path
                hadValue    = $current.found
                previous    = $(if ($current.found) { $current.value } else { $null })
                applied     = $change.value
            })
        }
        $changed++
    }
    if ($changed -gt 0) {
        Write-JsonFile $file $obj
        Save-Manifest $manifest
    }
    return $true
}

# Reverts tracked edits for one file. Values the student changed since setup are kept.
function Restore-TrackedJson($manifest, [string]$file, [string]$label) {
    $edits = @($manifest.jsonEdits | Where-Object { $_.file -eq $file })
    if ($edits.Count -eq 0) { return }
    if (-not (Test-Path $file)) { Write-Skip "$label no longer exists"; return }
    $read = Read-JsoncFile $file
    if (-not $read.ok) { Write-Warn2 "$label could not be read; restore it from the backup folder if needed: $file"; return }
    $obj = $read.obj
    $kept = @()
    foreach ($e in $edits) {
        $path = [string[]]@($e.path)
        $current = Get-PathValue $obj $path
        if ($current.found -and -not (Test-JsonEqual $current.value $e.applied)) {
            $kept += ($path -join '.')
            continue
        }
        if ($e.hadValue) { [void](Set-PathValue $obj $path $e.previous) }
        else { Remove-PathValue $obj $path }
    }
    $createdByUs = [bool]($edits | Where-Object { $_.createdFile } | Select-Object -First 1)
    if ($createdByUs -and @($obj.PSObject.Properties).Count -eq 0) {
        Remove-Item -Force $file
    } else {
        Write-JsonFile $file $obj
    }
    Write-Ok "$label restored"
    foreach ($k in $kept) { Write-Info "kept your newer value for $k" }
}

# ---------------------------------------------------------------- backups

function Backup-Files($manifest, [string[]]$paths) {
    $dir = Join-Path $script:StateDir ("backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $index = @()
    $n = 0
    foreach ($p in $paths) {
        if ($p -and (Test-Path $p)) {
            $n++
            $name = "{0:D2}-{1}" -f $n, (Split-Path $p -Leaf)
            Copy-Item -Force -Path $p -Destination (Join-Path $dir $name)
            $index += "$name <= $p"
        }
    }
    Set-Content -Path (Join-Path $dir 'index.txt') -Value $index
    Add-ToList $manifest 'backupDirs' $dir
    Save-Manifest $manifest
    return $dir
}

# ---------------------------------------------------------------- downloads

function Get-File([string]$url, [string]$dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -L --fail --retry 3 --retry-delay 2 --progress-bar -o $dest $url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $dest)) { return }
        Write-Warn2 'curl download failed, retrying with PowerShell'
    }
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ---------------------------------------------------------------- fonts

$script:FontRegNames = @{
    'MesloLGMNerdFont-Regular.ttf'    = 'MesloLGM Nerd Font Regular (TrueType)'
    'MesloLGMNerdFont-Bold.ttf'       = 'MesloLGM Nerd Font Bold (TrueType)'
    'MesloLGMNerdFont-Italic.ttf'     = 'MesloLGM Nerd Font Italic (TrueType)'
    'MesloLGMNerdFont-BoldItalic.ttf' = 'MesloLGM Nerd Font Bold Italic (TrueType)'
    'Hack-Regular.ttf'                = 'Hack Regular (TrueType)'
    'Hack-Bold.ttf'                   = 'Hack Bold (TrueType)'
    'Hack-Italic.ttf'                 = 'Hack Italic (TrueType)'
    'Hack-BoldItalic.ttf'             = 'Hack Bold Italic (TrueType)'
    'FiraCode-Regular.ttf'            = 'Fira Code Regular (TrueType)'
    'FiraCode-Medium.ttf'             = 'Fira Code Medium (TrueType)'
    'FiraCode-Bold.ttf'               = 'Fira Code Bold (TrueType)'
}

$script:UserFontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$script:MachineFontKey = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

if (-not ('NishantDsa.FontApi' -as [type])) {
    Add-Type -Namespace NishantDsa -Name FontApi -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern int AddFontResourceW(string file);
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern bool RemoveFontResourceW(string file);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
'@
}

function Send-FontChange {
    $r = [UIntPtr]::Zero
    [void][NishantDsa.FontApi]::SendMessageTimeoutW([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$r)
}

# A font counts as installed if its registry name exists for the user or the machine,
# or the same file name is already in a fonts folder.
function Test-FontInstalled([string]$fileName) {
    $reg = $script:FontRegNames[$fileName]
    foreach ($key in @($script:UserFontKey, $script:MachineFontKey)) {
        $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties[$reg]) { return $true }
    }
    if (Test-Path (Join-Path $env:WINDIR "Fonts\$fileName")) { return $true }
    if (Test-Path (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts\$fileName")) { return $true }
    return $false
}
