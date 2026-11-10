<#
.SYNOPSIS
    Installs this repo's OBS configuration into OBS Studio on this PC.

.DESCRIPTION
    Installs:
      - The scene collection, with every path rewritten to wherever this repo
        was cloned. The Lua scripts and their settings are part of the scene
        collection, so they are installed with it.
      - The scene collection becomes the active one in OBS.
      - The Aitum Vertical (vertical canvas) settings.
      - The IRZar font, for the current user only (no admin needed).
      - The VDO.Ninja stream ID, plus the git filter that keeps it out of commits.

    It does NOT install OBS or plugins yet.

    Safe to run again: files that are already up to date are left alone. If an
    installed file has different content, the script stops unless -Force is
    given. With -Force, the old file is backed up first (*.before-install-<time>).

.PARAMETER ObsConfigDir
    OBS's config folder. Default: %APPDATA%\obs-studio

.PARAMETER VdoNinjaId
    VDO.Ninja stream ID. If omitted, the one already stored in this repo's
    local git config is used, otherwise you are asked for it.

.PARAMETER Force
    Overwrite a scene collection or vertical config that differs from this repo
    (the old file is backed up first).

.PARAMETER SkipFont
    Do not install the font.

.EXAMPLE
    .\install.bat
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$ObsConfigDir = (Join-Path $env:APPDATA 'obs-studio'),
    [string]$VdoNinjaId,
    [switch]$Force,
    [switch]$SkipFont
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ObsConfigDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ObsConfigDir).TrimEnd('\')

# Show errors as one readable line instead of a PowerShell stack dump.
trap {
    Write-Host ''
    Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Repo layout -------------------------------------------------------------
$RepoRoot        = $PSScriptRoot
$SceneRel        = 'VazirifiedFX-dual-output-scene/VazirifiedFX-dual-output-scene-collection.json'
$SceneSrc        = Join-Path $RepoRoot $SceneRel
$VerticalSrc     = Join-Path $RepoRoot 'VazirifiedFX-dual-output-scene\vertical-canvas-config.json'
$FontSrc         = Join-Path $RepoRoot 'Fonts\IRZar.ttf'
$SceneFileName   = 'Double_Output_Vazirified_Channels.json'
$Placeholder     = '__VDO_NINJA_STREAM_ID__'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Read-Text([string]$Path) {
    # ReadAllText detects and drops a BOM.
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

# Writes $Content to $Path. Leaves it alone if already identical.
# If it differs: stops, unless $Overwrite, in which case the old file is backed up first.
function Install-TextFile {
    param(
        [string]$Path,
        [string]$Content,
        [System.Text.Encoding]$Encoding,
        [bool]$Overwrite,
        [string]$What
    )
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path -LiteralPath $Path) {
        if ((Read-Text $Path) -ceq $Content) {
            Write-Ok "$What already up to date: $Path"
            return
        }
        if (-not $Overwrite) {
            throw "$What on this PC differs from the repo: $Path`n    Nothing was changed. Run again with -Force to replace it (the current file will be backed up)."
        }
        $backup = "$Path.before-install-$Stamp"
        Copy-Item -LiteralPath $Path -Destination $backup
        Write-Note "Backed up the existing file to $backup"
    }
    [IO.File]::WriteAllText($Path, $Content, $Encoding)
    Write-Ok "$What installed: $Path"
}

function Invoke-Git {
    # Windows PowerShell 5.1 turns git's normal stderr chatter into errors under 'Stop', so relax it here.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try     { $output = & git -C $RepoRoot @args 2>$null }
    finally { $ErrorActionPreference = $previous }
    return $output
}

# --- 0. Preconditions -------------------------------------------------------
Write-Step 'Checking preconditions'

if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) {
    throw 'OBS is running. Close OBS and run this again.'
}
foreach ($f in $SceneSrc, $VerticalSrc) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Missing from the repo: $f" }
}
$haveGit = [bool](Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))
if (-not $haveGit) { Write-Note 'git or .git not found: the VDO.Ninja commit filter will not be set up.' }

# Warn if OBS has been pointed at custom config locations.
$globalIni = Join-Path $ObsConfigDir 'global.ini'
if (Test-Path -LiteralPath $globalIni) {
    $expectedBase = (Split-Path $ObsConfigDir -Parent).TrimEnd('\')
    foreach ($line in (Read-Text $globalIni) -split "`r?`n") {
        if ($line -match '^(Configuration|SceneCollections)=(.+)$') {
            $base = $Matches[2].Replace('\\', '\').TrimEnd('\')
            if ($base -ne $expectedBase) {
                Write-Note "OBS setting $($Matches[1]) points to '$base'. If OBS keeps its config there, rerun with -ObsConfigDir '$base\obs-studio'."
            }
        }
    }
}
Write-Ok "Repo:       $RepoRoot"
Write-Ok "OBS config: $ObsConfigDir"

# --- 1. VDO.Ninja stream ID and commit filter --------------------------------
Write-Step 'VDO.Ninja stream ID'

if (-not $VdoNinjaId -and $haveGit) { $VdoNinjaId = Invoke-Git config vdoninja.streamid }
if (-not $VdoNinjaId) {
    $VdoNinjaId = Read-Host '    Enter your VDO.Ninja stream ID (the v= value), or leave blank to skip'
}
if ($VdoNinjaId) {
    $VdoNinjaId = $VdoNinjaId.Trim()
    if ($VdoNinjaId -notmatch '^[A-Za-z0-9_-]+$') { throw "VDO.Ninja stream ID may only contain letters, digits, '_' and '-'." }
}

if ($haveGit) {
    Invoke-Git config filter.vdoninja.clean  'sh tools/vdoninja-filter.sh clean'  | Out-Null
    Invoke-Git config filter.vdoninja.smudge 'sh tools/vdoninja-filter.sh smudge' | Out-Null
    Invoke-Git config filter.vdoninja.required true | Out-Null
    if ($VdoNinjaId) {
        Invoke-Git config vdoninja.streamid $VdoNinjaId | Out-Null
        Write-Ok 'Stream ID saved in this repo''s local git config (never pushed).'
    }
    Write-Ok 'Commit filter set up: the ID is replaced by a placeholder in every commit.'

    # A fresh clone has the placeholder in its scene file. Check it out again so the smudge filter writes the real ID into it.
    if ($VdoNinjaId -and (Read-Text $SceneSrc).Contains($Placeholder)) {
        Remove-Item -LiteralPath $SceneSrc
        Invoke-Git checkout -- $SceneRel | Out-Null
        Write-Ok 'Scene file in the repo refreshed with the real ID.'
    }
}
if (-not $VdoNinjaId) { Write-Note 'No ID given: the VDO.Ninja source will not connect until you set its URL in OBS.' }

# --- 2. Scene collection (includes the Lua scripts) -------------------------
Write-Step 'Scene collection and scripts'

$scene = Read-Text $SceneSrc

# The folder the scene was saved from = location of Scripts/audio-transition.lua minus that part.
$m = [regex]::Match($scene, '"path"\s*:\s*"([^"]+)/Scripts/audio-transition\.lua"')
if (-not $m.Success) { throw 'Could not find where the scene collection was saved from (no Scripts/audio-transition.lua entry).' }
$oldRoot = $m.Groups[1].Value
$newRoot = ($RepoRoot -replace '\\', '/').TrimEnd('/')
$scene   = $scene.Replace("$oldRoot/", "$newRoot/")
if ($oldRoot -ne $newRoot) { Write-Ok "Paths rewritten: $oldRoot -> $newRoot" }

if ($VdoNinjaId) { $scene = $scene.Replace($Placeholder, $VdoNinjaId) }

$collectionName = ($scene | ConvertFrom-Json).name
if (-not $collectionName) { throw 'The scene collection has no name.' }

$sceneDest = Join-Path $ObsConfigDir "basic\scenes\$SceneFileName"
Install-TextFile -Path $sceneDest -Content $scene -Encoding $Utf8NoBom -Overwrite $Force.IsPresent -What 'Scene collection'

$scripts = [regex]::Matches($scene, '"path"\s*:\s*"([^"]+\.lua)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($s in $scripts) { Write-Ok "Script registered: $s" }

# --- 3. Make it the active scene collection ---------------------------------
Write-Step 'Active scene collection'

$userIni = Join-Path $ObsConfigDir 'user.ini'
$want = [ordered]@{ SceneCollection = $collectionName; SceneCollectionFile = $SceneFileName }
if (Test-Path -LiteralPath $userIni) {
    $lines = [Collections.Generic.List[string]]((Read-Text $userIni) -split "`r?`n")
} else {
    $lines = [Collections.Generic.List[string]]@()
}
$start = $lines.IndexOf('[Basic]')
if ($start -lt 0) {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
    $lines.Add('[Basic]'); $start = $lines.Count - 1
}
$end = $start + 1
while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
foreach ($key in $want.Keys) {
    $found = $false
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i].StartsWith("$key=")) { $lines[$i] = "$key=$($want[$key])"; $found = $true; break }
    }
    if (-not $found) { $lines.Insert($start + 1, "$key=$($want[$key])"); $end++ }
}
$newIni = ($lines -join "`n")
if (-not $newIni.EndsWith("`n")) { $newIni += "`n" }
Install-TextFile -Path $userIni -Content $newIni -Encoding $Utf8Bom -Overwrite $true -What 'OBS user settings'

# --- 4. Aitum Vertical settings ---------------------------------------------
Write-Step 'Aitum Vertical settings'

$vertical   = Read-Text $VerticalSrc
$profileEsc = $env:USERPROFILE.Replace('\', '\\')
$vertical   = [regex]::Replace($vertical,
    '("(?:record_path|backtrack_path)"\s*:\s*")[A-Za-z]:\\\\Users\\\\[^\\"]+',
    { param($x) $x.Groups[1].Value + $profileEsc })
$verticalDest = Join-Path $ObsConfigDir 'plugin_config\vertical-canvas\config.json'
Install-TextFile -Path $verticalDest -Content $vertical -Encoding $Utf8NoBom -Overwrite $Force.IsPresent -What 'Vertical canvas settings'

# --- 5. Font ----------------------------------------------------------------
Write-Step 'Font'

if ($SkipFont) {
    Write-Note 'Skipped (-SkipFont).'
} else {
    $fontName   = Split-Path $FontSrc -Leaf
    $userFonts  = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $installed  = (Test-Path -LiteralPath (Join-Path $env:WINDIR "Fonts\$fontName")) -or
                  (Test-Path -LiteralPath (Join-Path $userFonts $fontName))
    if ($installed) {
        Write-Ok "$fontName already installed."
    } else {
        if (-not (Test-Path -LiteralPath $userFonts)) { New-Item -ItemType Directory -Path $userFonts -Force | Out-Null }
        $fontDest = Join-Path $userFonts $fontName
        Copy-Item -LiteralPath $FontSrc -Destination $fontDest
        $regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
        if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
        New-ItemProperty -Path $regKey -Name ([IO.Path]::GetFileNameWithoutExtension($fontName) + ' (TrueType)') `
            -Value $fontDest -PropertyType String -Force | Out-Null
        Write-Ok "$fontName installed for the current user."
    }
}

# --- 6. Files the scene uses that are not in the repo -----------------------
Write-Step 'Media check'

$refs = [regex]::Matches($scene, '"(?:file|local_file|image_path|path|value)"\s*:\s*"(' + [regex]::Escape($newRoot) + '/[^"]+)"') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = @($refs | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -eq 0) {
    Write-Ok "All $(@($refs).Count) files and folders the scene uses are present."
} else {
    Write-Note "$($missing.Count) of $(@($refs).Count) files or folders the scene uses are missing (not in the repo, see README):"
    foreach ($p in $missing) { Write-Note "  - $p" }
}

Write-Host ''
Write-Host 'Done. Start OBS to use the setup.' -ForegroundColor Cyan
