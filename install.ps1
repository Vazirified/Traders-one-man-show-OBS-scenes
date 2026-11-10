<#
.SYNOPSIS
    Installs this repo's OBS configuration into OBS Studio on this PC.

.DESCRIPTION
    Installs:
      - OBS Studio, VLC and the OBS plugins this setup uses, each pinned to the
        version it was built with. Each installer is downloaded from its official
        source into .\installers, checked against a SHA-256 written in this
        script, and run silently. Anything already installed is left alone,
        even if its version differs. Installing needs admin rights, so Windows
        asks once (UAC) when something is missing.
      - The scene collection, with every path rewritten to wherever this repo
        was cloned. The Lua scripts and their settings are part of the scene
        collection, so they are installed with it.
      - The scene collection becomes the active one in OBS.
      - The Aitum Vertical (vertical canvas) settings.
      - The IRZar font, for the current user only (no admin needed).
      - The VDO.Ninja stream ID, plus the git filter that keeps it out of commits.
      - The live tickers (github.com/Vazirified/live-tickers, a separate repo):
        Python 3.14.2 for the current user if missing (no admin needed), a
        clone pinned to tag v2.0.0 in Scripts\live-tickers-v.2.0, and its
        setup.bat. An existing tickers folder is left alone. MetaTrader 5 is
        not installed (it needs your broker login); you are told if it's missing.

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

.PARAMETER SkipDependencies
    Do not check or install OBS, VLC and the plugins.

.PARAMETER SkipTickers
    Do not set up the live tickers (or Python).

.PARAMETER DownloadOnly
    Only download and check all pinned installers into .\installers (for an
    offline copy), then stop. Installs nothing.

.PARAMETER DependenciesOnly
    Used internally: the elevated (admin) run that installs missing dependencies.

.EXAMPLE
    .\install.bat
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Force
.EXAMPLE
    .\install.bat -DownloadOnly
#>
[CmdletBinding()]
param(
    [string]$ObsConfigDir = (Join-Path $env:APPDATA 'obs-studio'),
    [string]$VdoNinjaId,
    [switch]$Force,
    [switch]$SkipFont,
    [switch]$SkipDependencies,
    [switch]$SkipTickers,
    [switch]$DownloadOnly,
    [switch]$DependenciesOnly
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ObsConfigDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ObsConfigDir).TrimEnd('\')

# Show errors as one readable line instead of a PowerShell stack dump.
trap {
    Write-Host ''
    Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    if ($DependenciesOnly) { Read-Host 'Press Enter to close this window' | Out-Null }
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
$InstallerDir    = Join-Path $RepoRoot 'installers'

# --- Pinned dependencies -----------------------------------------------------
# Versions match the PC this setup was built on. To update one, change Version,
# Url and Sha256 together (GitHub shows each release file's sha256 digest).
# Match is a regex on the program's name in Windows "Installed apps"; installers
# run in this order (OBS first, the plugin installers look for it).
$InnoSilent = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
$Dependencies = @(
    @{ Name = 'OBS Studio';          Version = '33.0.1'; Match = '^OBS Studio$'
       Url  = 'https://github.com/obsproject/obs-studio/releases/download/33.0.1/OBS-Studio-33.0.1-Windows-x64-Installer.exe'
       Sha256 = '37ecde4d9a28e8aeeb07623c8469b5d558eb264e02ccf435bb859891c401758b'; Args = '/S' }
    @{ Name = 'VLC media player';    Version = '3.0.23'; Match = '^VLC media player$'
       Url  = 'https://download.videolan.org/pub/videolan/vlc/3.0.23/win64/vlc-3.0.23-win64.exe'
       Sha256 = '20ad191348684b470ddc4e05204316f3d8e39655f412b3e392a0eef97639daaf'; Args = '/S' }
    @{ Name = 'DroidCam OBS plugin'; Version = '2.5.1';  Match = '^DroidCam OBS Plugin'
       Url  = 'https://github.com/dev47apps/droidcam-obs-plugin/releases/download/2.5.1/DroidCamOBS.Setup.2.5.1.exe'
       Sha256 = 'fb20d899cd2aa45b3670e7ee10a5e90130dc489321770dd271b701d82522db31'; Args = '/S' }
    @{ Name = 'Move Transition';     Version = '3.2.1';  Match = '^move-transition version'
       Url  = 'https://github.com/exeldro/obs-move-transition/releases/download/3.2.1/move-transition-3.2.1-windows-installer.exe'
       Sha256 = 'a3777ac68c0e7c86dbab8ea94146dbf4a48223e128696c32defd99ddaa56f8c8'; Args = $InnoSilent }
    @{ Name = 'Aitum Vertical';      Version = '1.6.1';  Match = '^vertical-canvas version'
       Url  = 'https://github.com/Aitum/obs-vertical-canvas/releases/download/1.6.1/vertical-canvas-windows-installer.exe'
       Sha256 = '455dc673290b7098a72b1c72705b86ad80118e2fefd149970f566ad64dd6ee6c'; Args = $InnoSilent }
    @{ Name = 'Face Tracker';        Version = '0.9.0';  Match = '^obs-face-tracker version'
       Url  = 'https://github.com/norihiro/obs-face-tracker/releases/download/0.9.0/obs-face-tracker-0.9.0-obs30-Windows-Installer.exe'
       Sha256 = 'cd344c60f2df8c9e6af98a2821cf52f7ed1b25221c25f20b889d53b2bb1864f6'; Args = $InnoSilent }
)

# Live tickers: their own repo, cloned next to the other scripts. OBS loads them
# from http://localhost:5000 (started by the tickers' run.bat), not from disk.
$TickersUrl = 'https://github.com/Vazirified/live-tickers.git'
$TickersTag = 'v2.0.0'
$TickersDir = Join-Path $RepoRoot 'Scripts\live-tickers-v.2.0'

# Python for the tickers' virtual environment. Installed for the current user
# only, so it needs no admin rights.
$Python = @{ Name = 'Python'; Version = '3.14.2'; Minor = '3.14'
    Url    = 'https://www.python.org/ftp/python/3.14.2/python-3.14.2-amd64.exe'
    Sha256 = '9db919cefe30a0051658c600a9912acb0cd2b872aaf35842c9ec2bf401efa848'
    Args   = '/quiet InstallAllUsers=0 InstallLauncherAllUsers=0 PrependPath=1 Include_test=0' }

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

# Programs in Windows "Installed apps" (64-bit, 32-bit and per-user).
function Get-InstalledApp {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] } |
        ForEach-Object {
            $version = if ($_.PSObject.Properties['DisplayVersion']) { $_.DisplayVersion } else { '' }
            [pscustomobject]@{ Name = $_.DisplayName; Version = $version }
        }
}

# Returns the dependencies that are not installed at all, and reports the rest.
function Get-MissingDependency([bool]$Quiet) {
    $apps = @(Get-InstalledApp)
    foreach ($d in $Dependencies) {
        $hit = $apps | Where-Object { $_.Name -match $d.Match } | Select-Object -First 1
        if (-not $hit) {
            if (-not $Quiet) { Write-Note "$($d.Name) $($d.Version): not installed" }
            $d
        } elseif ($Quiet) {
        } elseif ($hit.Version -eq $d.Version) {
            Write-Ok "$($d.Name) $($d.Version) installed."
        } else {
            Write-Note "$($d.Name): $($hit.Version) installed, this repo pins $($d.Version). Left as is."
        }
    }
}

# Downloads a dependency's installer into $InstallerDir and checks its SHA-256.
# A file that is already there and matches is reused. Returns the file path.
function Save-Installer($Dep) {
    if (-not (Test-Path -LiteralPath $InstallerDir)) { New-Item -ItemType Directory -Path $InstallerDir | Out-Null }
    $file = Join-Path $InstallerDir ([IO.Path]::GetFileName(([uri]$Dep.Url).AbsolutePath))
    if ((Test-Path -LiteralPath $file) -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $Dep.Sha256) {
        Write-Ok "$($Dep.Name) $($Dep.Version): already downloaded, checksum OK."
        return $file
    }
    Write-Host "    $($Dep.Name) $($Dep.Version): downloading $($Dep.Url)"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $partial = "$file.part"
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow in Windows PowerShell
    try     { Invoke-WebRequest -Uri $Dep.Url -OutFile $partial -UseBasicParsing }
    finally { $ProgressPreference = $previous }
    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
    if ($hash -ne $Dep.Sha256) {
        Remove-Item -LiteralPath $partial
        throw "Checksum mismatch for $($Dep.Name) (got $hash, expected $($Dep.Sha256)). The download was deleted and not run."
    }
    Move-Item -LiteralPath $partial -Destination $file -Force
    Write-Ok "$($Dep.Name) $($Dep.Version): downloaded, checksum OK."
    return $file
}

function Install-Dependency($Dep) {
    $file = Save-Installer $Dep
    Write-Host "    $($Dep.Name) $($Dep.Version): installing..."
    $p = Start-Process -FilePath $file -ArgumentList $Dep.Args -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$($Dep.Name) installer failed (exit code $($p.ExitCode))." }
    Write-Ok "$($Dep.Name) $($Dep.Version) installed."
}

# Finds Python <Minor> through the registry entries every Python installer writes
# (PEP 514). Returns @{ Exe; Version } or $null.
function Find-Python([string]$Minor) {
    foreach ($root in 'HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore') {
        $key = "$root\$Minor\InstallPath"
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty $key
        $exe = if ($props.PSObject.Properties['ExecutablePath']) { $props.ExecutablePath }
               elseif ($props.PSObject.Properties['(default)']) { Join-Path $props.'(default)' 'python.exe' }
               else { $null }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            $version = (& $exe -c 'import platform; print(platform.python_version())').Trim()
            return @{ Exe = $exe; Version = $version }
        }
    }
    return $null
}

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Download-only mode -----------------------------------------------------
if ($DownloadOnly) {
    Write-Step "Downloading pinned installers into $InstallerDir"
    foreach ($d in $Dependencies + $Python) { Save-Installer $d | Out-Null }
    Write-Host ''
    Write-Host 'Done. Nothing was installed.' -ForegroundColor Cyan
    exit 0
}

# --- 0. Preconditions -------------------------------------------------------
Write-Step 'Checking preconditions'

if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) {
    throw 'OBS is running. Close OBS and run this again.'
}

# --- Elevated run: install missing dependencies only ------------------------
if ($DependenciesOnly) {
    Write-Step 'Installing missing OBS, VLC and plugins (admin)'
    foreach ($d in @(Get-MissingDependency $true)) { Install-Dependency $d }
    Write-Host ''
    Write-Host 'Done. This window closes in 5 seconds.' -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    exit 0
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

# --- 1. OBS, VLC and plugins ------------------------------------------------
Write-Step 'OBS, VLC and plugins'

if ($SkipDependencies) {
    Write-Note 'Skipped (-SkipDependencies).'
} else {
    $missing = @(Get-MissingDependency $false)
    if ($missing.Count -gt 0) {
        if (Test-Admin) {
            foreach ($d in $missing) { Install-Dependency $d }
        } else {
            Write-Host "    Installing $($missing.Count) program(s) needs admin rights. Windows will ask for permission..."
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -DependenciesOnly"
            try {
                $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
            } catch {
                throw 'Admin permission was refused, so OBS, VLC and the plugins were not installed. Run again to retry, or use -SkipDependencies.'
            }
            if ($p.ExitCode -ne 0) { throw "Installing the dependencies failed (exit code $($p.ExitCode)). See the admin window's message." }
        }
        $still = @(Get-MissingDependency $true)
        if ($still.Count -gt 0) { throw "Still not installed after running the installers: $(($still | ForEach-Object { $_.Name }) -join ', ')" }
        Write-Ok 'All dependencies installed.'
    }
}

# --- 2. VDO.Ninja stream ID and commit filter --------------------------------
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

# --- 3. Scene collection (includes the Lua scripts) -------------------------
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

# --- 4. Make it the active scene collection ---------------------------------
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

# --- 5. Aitum Vertical settings ---------------------------------------------
Write-Step 'Aitum Vertical settings'

$vertical   = Read-Text $VerticalSrc
$profileEsc = $env:USERPROFILE.Replace('\', '\\')
$vertical   = [regex]::Replace($vertical,
    '("(?:record_path|backtrack_path)"\s*:\s*")[A-Za-z]:\\\\Users\\\\[^\\"]+',
    { param($x) $x.Groups[1].Value + $profileEsc })
$verticalDest = Join-Path $ObsConfigDir 'plugin_config\vertical-canvas\config.json'
Install-TextFile -Path $verticalDest -Content $vertical -Encoding $Utf8NoBom -Overwrite $Force.IsPresent -What 'Vertical canvas settings'

# --- 6. Font ----------------------------------------------------------------
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

# --- 7. Live tickers --------------------------------------------------------
Write-Step 'Live tickers'

if ($SkipTickers) {
    Write-Note 'Skipped (-SkipTickers).'
} else {
    $tickersVenv = Join-Path $TickersDir '.venv\Scripts\python.exe'
    $tickersRel  = $TickersDir.Substring($RepoRoot.Length + 1)

    # Clone, unless a tickers folder is already there (never touch a working copy).
    if (Test-Path -LiteralPath $TickersDir) {
        $describe = if (Test-Path -LiteralPath (Join-Path $TickersDir '.git')) {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { (& git -C $TickersDir describe --tags --always --dirty 2>$null) } finally { $ErrorActionPreference = $prev }
        } else { 'not a git repo' }
        Write-Ok "$tickersRel already present ($describe). Left as is."
    } else {
        if (-not $haveGit) { throw 'git is needed to download the live tickers. Install Git for Windows, or use -SkipTickers.' }
        Write-Host "    Cloning $TickersUrl at $TickersTag..."
        Invoke-Git -c advice.detachedHead=false clone --quiet --branch $TickersTag $TickersUrl $tickersRel | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $TickersDir 'setup.bat'))) {
            throw "Could not clone the live tickers from $TickersUrl (exit code $LASTEXITCODE)."
        }
        Write-Ok "Cloned into $tickersRel at $TickersTag."
    }

    # Virtual environment, via the tickers' own setup.bat, unless it already exists.
    if (Test-Path -LiteralPath $tickersVenv) {
        Write-Ok 'Python environment already set up.'
    } else {
        $py = Find-Python $Python.Minor
        if (-not $py) {
            Write-Host "    Python $($Python.Version) not found, installing it for the current user..."
            $file = Save-Installer $Python
            $p = Start-Process -FilePath $file -ArgumentList $Python.Args -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "Python installer failed (exit code $($p.ExitCode))." }
            $py = Find-Python $Python.Minor
            if (-not $py) { throw "Python $($Python.Version) was installed but could not be found." }
            Write-Ok "Python $($py.Version) installed."
        } elseif ($py.Version -ne $Python.Version) {
            Write-Note "Using Python $($py.Version) (this repo pins $($Python.Version))."
        } else {
            Write-Ok "Python $($py.Version) found."
        }

        # Put this Python first on PATH for setup.bat. The empty input answers its
        # final 'pause'. '.\' because some PCs block running files from the current
        # folder by bare name (NoDefaultCurrentDirectoryInExePath).
        Write-Host '    Running the tickers'' setup.bat (creates .venv, installs packages)...'
        $pyDir = Split-Path $py.Exe -Parent
        $previousPath = $env:Path
        $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
        Push-Location -LiteralPath $TickersDir
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try     { '' | & cmd.exe /d /c .\setup.bat | ForEach-Object { "      $_" } | Write-Host }
        finally { $ErrorActionPreference = $prev; Pop-Location; $env:Path = $previousPath }

        # setup.bat always exits 0, so the import check below is what decides.
        if (-not (Test-Path -LiteralPath $tickersVenv)) { throw 'setup.bat did not create the .venv folder.' }
        Write-Ok 'Python environment created.'
    }

    # Health check, also for an existing environment. (No double quotes in the
    # Python code: Windows PowerShell 5.1 strips them from native arguments.)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try     { $check = & $tickersVenv -c "import sys, MetaTrader5, flask, flask_socketio; print('ok', sys.version.split()[0])" 2>&1 }
    finally { $ErrorActionPreference = $prev }
    if ("$check" -notmatch '^ok (\S+)$') { throw "The tickers' Python packages do not load: $check" }
    Write-Ok "Tickers' packages load correctly (Python $($Matches[1]))."

    if (@(Get-InstalledApp | Where-Object { $_.Name -match 'MetaTrader 5' }).Count -gt 0) {
        Write-Ok 'MetaTrader 5 is installed.'
    } else {
        Write-Note 'MetaTrader 5 is not installed. The tickers read prices from it: install your broker''s MetaTrader 5 and log in.'
    }
    Write-Ok "Start the tickers with $tickersRel\run.bat before going live (OBS reads http://localhost:5000)."
}

# --- 8. Files the scene uses that are not in the repo -----------------------
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
