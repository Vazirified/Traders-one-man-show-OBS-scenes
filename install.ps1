<#
.SYNOPSIS
    Installs this repo's OBS setup on this PC.

.DESCRIPTION
    Installs:
      - OBS Studio, VLC and the OBS plugins this setup uses, at their LATEST
        release. Each one also records the version this setup was last tested
        with; installing anything newer prints a warning. Each installer is
        downloaded from its official source into .\installers, checked against
        the SHA-256 its publisher lists and against its code signature, then
        run silently. Programs that are already installed are only reported
        when a newer version exists; -Upgrade installs it. Installing needs
        admin rights, so Windows asks once (UAC).
      - The scene collection, with every path rewritten to wherever this repo
        was cloned. The Lua scripts and their settings are part of the scene
        collection, so they are installed with it.
      - The Audio Transition script by dqm, which isn't part of this repo: its
        latest version is downloaded from the OBS forum into Scripts\, with a
        warning when it differs from the tested version. An existing copy is
        only replaced with -Upgrade.
      - The scene collection becomes the active one in OBS.
      - The Aitum Vertical (vertical canvas) settings.
      - The IRZar font, for the current user only (no admin needed), if you've
        put IRZar.ttf in Fonts\. It isn't part of this repo (see README).
      - The VDO.Ninja stream ID, plus the git filter that keeps it out of commits.
      - The live tickers (github.com/Vazirified/live-tickers, a separate repo),
        following the latest commit on its main branch: cloned into
        Scripts\live-tickers-v.2.0, or an existing clone updated when it has no
        local changes. Python 3.14.2 is installed for the current user if
        missing, and the tickers' setup.bat runs when .venv is missing or
        requirements.txt changed. MetaTrader 5 is not installed (it needs your
        broker login); you are told if it's missing.

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

.PARAMETER Upgrade
    Also upgrade OBS, VLC and plugins that are installed at an older version.
    Without it, installed programs are never changed.

.PARAMETER Tested
    Use the last tested versions instead of the latest releases (for new
    installs and -Upgrade). Never downgrades anything.

.PARAMETER SkipFont
    Do not install the font.

.PARAMETER SkipDependencies
    Do not check or install OBS, VLC and the plugins.

.PARAMETER SkipTickers
    Do not set up or update the live tickers (or Python).

.PARAMETER DownloadOnly
    Only download and verify the installers a run would use (latest, or the
    tested ones with -Tested) into .\installers, then stop. Installs nothing.

.PARAMETER DependenciesOnly
    Used internally: the elevated (admin) run that installs dependencies.

.EXAMPLE
    .\install.bat
.EXAMPLE
    .\install.bat -Upgrade
.EXAMPLE
    .\install.bat -Tested
.EXAMPLE
    .\install.bat -DownloadOnly
#>
[CmdletBinding()]
param(
    [string]$ObsConfigDir = (Join-Path $env:APPDATA 'obs-studio'),
    [string]$VdoNinjaId,
    [switch]$Force,
    [switch]$Upgrade,
    [switch]$Tested,
    [switch]$SkipFont,
    [switch]$SkipDependencies,
    [switch]$SkipTickers,
    [switch]$DownloadOnly,
    [switch]$DependenciesOnly
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ObsConfigDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ObsConfigDir).TrimEnd('\')
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

# --- Dependencies: latest release, with the last tested version on record -----
# A run installs the newest release of each. "Tested" is the version this setup
# was last checked with; installing any other version prints a warning. After
# testing a newer version, copy its Version, Url and Sha256 into Tested (GitHub
# shows each release file's sha256). Tested is also what -Tested installs, and
# the fallback when the latest release can't be looked up.
#   Match:  regex on the program's name in Windows "Installed apps"
#   Signer: publisher expected in the installer's code signature
#   Assets: regexes for the release file, first match wins ({ObsMajor} = OBS major version)
# Installers run in this order (OBS first: the plugin installers look for it).
$InnoSilent = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
$Dependencies = @(
    @{ Name = 'OBS Studio'; Match = '^OBS Studio$'; Args = '/S'; Signer = 'OBS Project'
       Repo = 'obsproject/obs-studio'; Assets = @('^OBS-Studio-[\d.]+-Windows-x64-Installer\.exe$')
       Tested = @{ Version = '33.0.1'
           Url    = 'https://github.com/obsproject/obs-studio/releases/download/33.0.1/OBS-Studio-33.0.1-Windows-x64-Installer.exe'
           Sha256 = '37ecde4d9a28e8aeeb07623c8469b5d558eb264e02ccf435bb859891c401758b' } }
    @{ Name = 'VLC media player'; Match = '^VLC media player$'; Args = '/S'; Signer = 'VideoLAN'
       Tested = @{ Version = '3.0.23'
           Url    = 'https://download.videolan.org/pub/videolan/vlc/3.0.23/win64/vlc-3.0.23-win64.exe'
           Sha256 = '20ad191348684b470ddc4e05204316f3d8e39655f412b3e392a0eef97639daaf' } }
    @{ Name = 'DroidCam OBS plugin'; Match = '^DroidCam OBS Plugin'; Args = '/S'; Signer = 'DEV47 APPS'
       Repo = 'dev47apps/droidcam-obs-plugin'
       # The build made for the OBS major version in use if there is one, else the general build.
       Assets = @('^DroidCamOBS\.Setup\.[\d.]+\.obs{ObsMajor}_\d+\.exe$', '^DroidCamOBS\.Setup\.[\d.]+\.exe$')
       Tested = @{ Version = '2.5.1'
           Url    = 'https://github.com/dev47apps/droidcam-obs-plugin/releases/download/2.5.1/DroidCamOBS.Setup.2.5.1.exe'
           Sha256 = 'fb20d899cd2aa45b3670e7ee10a5e90130dc489321770dd271b701d82522db31' } }
    @{ Name = 'Move Transition'; Match = '^move-transition version'; Args = $InnoSilent; Signer = 'Exeldro'
       Repo = 'exeldro/obs-move-transition'; Assets = @('^move-transition-[\d.]+-windows-installer\.exe$')
       Tested = @{ Version = '3.2.1'
           Url    = 'https://github.com/exeldro/obs-move-transition/releases/download/3.2.1/move-transition-3.2.1-windows-installer.exe'
           Sha256 = 'a3777ac68c0e7c86dbab8ea94146dbf4a48223e128696c32defd99ddaa56f8c8' } }
    @{ Name = 'Aitum Vertical'; Match = '^vertical-canvas version'; Args = $InnoSilent; Signer = 'Aitum'
       Repo = 'Aitum/obs-vertical-canvas'; Assets = @('^vertical-canvas-windows-installer\.exe$')
       Tested = @{ Version = '1.6.1'
           Url    = 'https://github.com/Aitum/obs-vertical-canvas/releases/download/1.6.1/vertical-canvas-windows-installer.exe'
           Sha256 = '455dc673290b7098a72b1c72705b86ad80118e2fefd149970f566ad64dd6ee6c' } }
    @{ Name = 'Face Tracker'; Match = '^obs-face-tracker version'; Args = $InnoSilent; Signer = 'Norihiro Kamae'
       Repo = 'norihiro/obs-face-tracker'; Assets = @('^obs-face-tracker-[\d.]+-obs\d+-Windows-Installer\.exe$')
       Tested = @{ Version = '0.9.0'
           Url    = 'https://github.com/norihiro/obs-face-tracker/releases/download/0.9.0/obs-face-tracker-0.9.0-obs30-Windows-Installer.exe'
           Sha256 = 'cd344c60f2df8c9e6af98a2821cf52f7ed1b25221c25f20b889d53b2bb1864f6' } }
)

# Live tickers: their own repo, following the latest commit on main. OBS loads
# them from http://localhost:5000 (started by the tickers' run.bat), not from disk.
$TickersUrl    = 'https://github.com/Vazirified/live-tickers.git'
$TickersBranch = 'main'
$TickersDir    = Join-Path $RepoRoot 'Scripts\live-tickers-v.2.0'

# Python for the tickers' virtual environment. Stays pinned: the MetaTrader5
# package only ships for particular Python versions. Installed for the current
# user only, so it needs no admin rights.
$Python = @{ Name = 'Python'; Minor = '3.14'; Signer = 'Python Software Foundation'
    Args   = '/quiet InstallAllUsers=0 InstallLauncherAllUsers=0 PrependPath=1 Include_test=0'
    Tested = @{ Version = '3.14.2'
        Url    = 'https://www.python.org/ftp/python/3.14.2/python-3.14.2-amd64.exe'
        Sha256 = '9db919cefe30a0051658c600a9912acb0cd2b872aaf35842c9ec2bf401efa848' } }

# Audio Transition script by dqm. Published as a zip on the OBS forum (no git
# repo, no license to share it), so it's downloaded into Scripts\ instead of
# being part of this repo. No checksum is published: the SHA-256 recorded here
# is of audio-transition.lua in the tested version, and any other file prints a
# warning.
$AudioTransition = @{ Name = 'Audio Transition script'; Entry = 'audio-transition.lua'
    Page      = 'https://obsproject.com/forum/resources/audio-transition.2117/'
    LatestUrl = 'https://obsproject.com/forum/resources/audio-transition.2117/download'
    Tested    = @{ Version = '1.1'
        Url    = 'https://obsproject.com/forum/resources/audio-transition.2117/version/6177/download'
        Sha256 = '2964875db4f60df11823da92ab35351d4fe873c6e755bbbadb37a2a1c8920e8a' } }
$AudioTransitionDest = Join-Path $RepoRoot 'Scripts\audio-transition.lua'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$GitHubHeaders = @{ 'User-Agent' = 'obs-setup-installer'; 'Accept' = 'application/vnd.github+json' }
$ResolvedReleases = @{}

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

# Runs git in this repo. Windows PowerShell 5.1 turns git's normal stderr
# chatter into errors under 'Stop', so relax it here. $LASTEXITCODE is kept.
function Invoke-Git {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try     { $output = & git -C $RepoRoot @args 2>$null }
    finally { $ErrorActionPreference = $previous }
    return $output
}

# Same, in another folder (the first argument).
function Invoke-GitIn([string]$Dir) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try     { $output = & git -C $Dir @args 2>$null }
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

# -1, 0 or 1. Numeric where both sides parse as versions, text otherwise.
function Compare-Version([string]$A, [string]$B) {
    $va = $null; $vb = $null
    if ([version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb)) { return [math]::Sign($va.CompareTo($vb)) }
    return [math]::Sign([string]::CompareOrdinal($A, $B))
}

function Get-WebText([string]$Url) {
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    if ($content -is [byte[]]) { $content = [Text.Encoding]::ASCII.GetString($content) }
    return [string]$content
}

# The newest release of a dependency: @{ Version; Url; Sha256 (or $null); Latest }.
function Get-LatestRelease($Dep, [string]$ObsMajor) {
    if ($Dep.ContainsKey('Repo')) {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Dep.Repo)/releases/latest" -Headers $GitHubHeaders -UseBasicParsing
        $version = $release.tag_name -replace '^[vV]', ''
        foreach ($pattern in $Dep.Assets) {
            $pattern = $pattern.Replace('{ObsMajor}', $ObsMajor)
            $asset = @($release.assets | Where-Object { $_.name -match $pattern } | Sort-Object name) | Select-Object -Last 1
            if ($asset) {
                $sha = $null
                if ($asset.PSObject.Properties['digest'] -and "$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1] }
                return @{ Version = $version; Url = $asset.browser_download_url; Sha256 = $sha; Latest = $true }
            }
        }
        throw "release $version has no matching Windows installer"
    }
    # VLC: VideoLAN keeps the newest release in 'last', with a .sha256 file next to the installer.
    $base = 'https://download.videolan.org/pub/videolan/vlc'
    $page = Get-WebText "$base/last/win64/"
    if ($page -notmatch 'vlc-(\d+(?:\.\d+)+)-win64\.exe"') { throw 'no installer found in the download folder' }
    $version = $Matches[1]
    $url = "$base/$version/win64/vlc-$version-win64.exe"
    if ((Get-WebText "$url.sha256") -notmatch '^([0-9a-fA-F]{64})\s') { throw 'no checksum file for the installer' }
    return @{ Version = $version; Url = $url; Sha256 = $Matches[1]; Latest = $true }
}

# What to install for a dependency: the latest release, or the tested version
# with -Tested or when the lookup fails. Looked up once per run.
function Resolve-Target($Dep, [string]$ObsMajor) {
    if ($ResolvedReleases.ContainsKey($Dep.Name)) { return $ResolvedReleases[$Dep.Name] }
    # $script: so a caller's local variable can't shadow the switch (names are case-insensitive).
    if ($script:Tested) {
        $target = $Dep.Tested + @{ Latest = $false }
    } else {
        try {
            $target = Get-LatestRelease $Dep $ObsMajor
        } catch {
            Write-Note "$($Dep.Name): could not look up the latest release ($($_.Exception.Message)). Using the last tested version, $($Dep.Tested.Version)."
            $target = $Dep.Tested + @{ Latest = $false }
        }
    }
    $ResolvedReleases[$Dep.Name] = $target
    return $target
}

# Compares installed versions with the target versions and returns, in install
# order, the @{ Dep; Release } entries to install. Reports each one unless $Quiet.
function Get-DependencyPlan([bool]$Quiet) {
    $apps = @(Get-InstalledApp)
    $obsMajor = ''
    foreach ($d in $Dependencies) {
        $hit       = $apps | Where-Object { $_.Name -match $d.Match } | Select-Object -First 1
        $installed = if ($hit) { "$($hit.Version)" } else { $null }
        $target    = Resolve-Target $d $obsMajor
        $testedVersion = $d.Tested.Version
        $kind      = if ($target.Latest) { 'latest' } else { 'tested' }
        $warning   = if ($target.Version -ne $testedVersion) { " WARNING: not tested with this setup yet (last tested: $testedVersion)." } else { '' }
        $install   = $false

        if (-not $installed) {
            if (-not $Quiet) { Write-Note "$($d.Name): not installed. Will install $($target.Version) ($kind).$warning" }
            $install = $true
        } elseif ((Compare-Version $installed $target.Version) -lt 0) {
            if ($script:Upgrade) {
                if (-not $Quiet) { Write-Note "$($d.Name): will upgrade $installed to $($target.Version) ($kind).$warning" }
                $install = $true
            } elseif (-not $Quiet) {
                $testedInfo = if ($target.Version -ne $testedVersion) { "not tested with this setup yet; last tested: $testedVersion" } else { 'tested' }
                Write-Note "$($d.Name) $installed installed. Newer $kind version $($target.Version) is available ($testedInfo). Run install.bat -Upgrade to install it."
            }
        } elseif (-not $Quiet) {
            if ($installed -eq $testedVersion) { Write-Ok "$($d.Name) $installed installed (tested)." }
            else { Write-Note "$($d.Name) $installed installed. Not tested with this setup yet (last tested: $testedVersion)." }
        }

        if ($d.Name -eq 'OBS Studio') {
            $obsVersion = if ($install -or -not $installed) { $target.Version } else { $installed }
            $obsMajor = ($obsVersion -split '\.')[0]
        }
        if ($install) { @{ Dep = $d; Release = $target } }
    }
}

# Checks an installer file: its SHA-256 (when one is known) and its code signature.
# Returns $null when it's fine, otherwise what's wrong.
function Get-InstallerProblem([string]$File, $Release, [string]$Signer) {
    if ($Release.Sha256) {
        $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
        if ($hash -ne $Release.Sha256) { return "checksum mismatch (got $hash, expected $($Release.Sha256))" }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    if ($signature.Status -ne 'Valid') { return "code signature is not valid ($($signature.Status))" }
    if ($signature.SignerCertificate.Subject -notmatch [regex]::Escape($Signer)) {
        return "signed by '$($signature.SignerCertificate.Subject)', expected '$Signer'"
    }
    return $null
}

# Downloads an installer into $InstallerDir\<name> <version>\ and verifies it.
# A verified file that is already there is reused. Returns the file path.
function Save-Installer($Dep, $Release) {
    $label  = "$($Dep.Name) $($Release.Version)"
    $folder = Join-Path $InstallerDir $label
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $file = Join-Path $folder ([IO.Path]::GetFileName(([uri]$Release.Url).AbsolutePath))
    $checks = if ($Release.Sha256) { 'checksum and signature OK' } else { 'signature OK (no checksum published)' }

    if ((Test-Path -LiteralPath $file) -and -not (Get-InstallerProblem $file $Release $Dep.Signer)) {
        Write-Ok "${label}: already downloaded, $checks."
        return $file
    }
    Write-Host "    ${label}: downloading $($Release.Url)"
    $partial = "$file.part"
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow in Windows PowerShell
    try     { Invoke-WebRequest -Uri $Release.Url -OutFile $partial -UseBasicParsing }
    finally { $ProgressPreference = $previous }
    $problem = Get-InstallerProblem $partial $Release $Dep.Signer
    if ($problem) {
        Remove-Item -LiteralPath $partial
        throw "${label}: $problem. The download was deleted and not run."
    }
    Move-Item -LiteralPath $partial -Destination $file -Force
    Write-Ok "${label}: downloaded, $checks."
    return $file
}

function Install-Dependency($Item) {
    $d = $Item.Dep; $r = $Item.Release
    $file = Save-Installer $d $r
    Write-Host "    $($d.Name) $($r.Version): installing..."
    $p = Start-Process -FilePath $file -ArgumentList $d.Args -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$($d.Name) installer failed (exit code $($p.ExitCode))." }
    Write-Ok "$($d.Name) $($r.Version) installed."
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

# Brings an existing tickers clone to the latest commit on $TickersBranch, but
# only when that is safe: right repo, no local changes, no local-only commits.
# Returns $true if requirements.txt changed (packages need reinstalling).
function Update-TickersClone([string]$Rel) {
    $norm   = { param($u) ("$u" -replace '\.git$', '').TrimEnd('/').ToLowerInvariant() }
    $origin = Invoke-GitIn $TickersDir remote get-url origin
    if ((& $norm $origin) -ne (& $norm $TickersUrl)) {
        Write-Note "$Rel comes from '$origin', not $TickersUrl. Not updated."
        return $false
    }
    if (@(Invoke-GitIn $TickersDir status --porcelain).Count -gt 0) {
        Write-Note "$Rel has local changes. Not updated: commit or discard them to get the latest version."
        return $false
    }
    $before = Invoke-GitIn $TickersDir rev-parse HEAD
    Invoke-GitIn $TickersDir fetch --quiet origin $TickersBranch | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Note "Could not reach GitHub to check for ticker updates. Using the version already here."
        return $false
    }
    $branch = Invoke-GitIn $TickersDir rev-parse --abbrev-ref HEAD
    if ($branch -eq 'HEAD') {
        # Detached, e.g. checked out at a tag by an earlier version of this installer.
        if (Invoke-GitIn $TickersDir rev-parse --verify --quiet "refs/heads/$TickersBranch") {
            Invoke-GitIn $TickersDir checkout --quiet $TickersBranch | Out-Null
        } else {
            Invoke-GitIn $TickersDir checkout --quiet -b $TickersBranch --track "origin/$TickersBranch" | Out-Null
        }
        if ($LASTEXITCODE -ne 0) { Write-Note "Could not switch $Rel to $TickersBranch. Not updated."; return $false }
    } elseif ($branch -ne $TickersBranch) {
        Write-Note "$Rel is on branch '$branch', not $TickersBranch. Not updated."
        return $false
    }
    Invoke-GitIn $TickersDir merge --ff-only --quiet "origin/$TickersBranch" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Note "$Rel has commits that are not on GitHub's $TickersBranch. Not updated: push or reset them first."
        return $false
    }
    $after = Invoke-GitIn $TickersDir rev-parse HEAD
    $now   = Invoke-GitIn $TickersDir describe --tags --always
    $ahead = [int](Invoke-GitIn $TickersDir rev-list --count "origin/$TickersBranch..HEAD")
    if ($before -eq $after) {
        if ($ahead -gt 0) { Write-Note "$Rel has $ahead commit(s) that are not on GitHub yet ($now). Left as is." }
        else              { Write-Ok "$Rel is already at the latest $TickersBranch ($now)." }
        return $false
    }
    Write-Ok "$Rel updated to the latest $TickersBranch ($now)."
    Invoke-GitIn $TickersDir diff --quiet $before $after -- requirements.txt | Out-Null
    return ($LASTEXITCODE -ne 0)
}

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The version written in the Audio Transition script: version = "v1.1 by DQM ...".
function Get-AudioTransitionVersion([string]$Text) {
    if ($Text -match 'version\s*=\s*"v?(\d+(?:\.\d+)+)') { return $Matches[1] }
    return $null
}

# Downloads the Audio Transition zip (the latest, or the tested version) into
# $InstallerDir\Audio Transition script <version>\ and returns
# @{ Bytes; Version; IsTested } for audio-transition.lua inside it.
function Get-AudioTransitionRelease([bool]$UseTested) {
    $url = if ($UseTested) { $AudioTransition.Tested.Url } else { $AudioTransition.LatestUrl }
    if (-not (Test-Path -LiteralPath $InstallerDir)) { New-Item -ItemType Directory -Path $InstallerDir | Out-Null }
    $partial = Join-Path $InstallerDir 'audio-transition.zip.part'
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try     { Invoke-WebRequest -Uri $url -OutFile $partial -UseBasicParsing }
    finally { $ProgressPreference = $previous }

    # Read only the one expected file from the zip (nothing is extracted to disk).
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($partial)
    try {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq $AudioTransition.Entry } | Select-Object -First 1
        if (-not $entry) { throw "the download has no $($AudioTransition.Entry)" }
        $stream = $entry.Open()
        try     { $buffer = New-Object IO.MemoryStream; $stream.CopyTo($buffer); $bytes = $buffer.ToArray() }
        finally { $stream.Dispose() }
    } finally { $archive.Dispose() }

    $sha  = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '')
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text -notmatch 'obslua' -or $text -notmatch 'Audio Transition') {
        Remove-Item -LiteralPath $partial
        throw 'the download is not the Audio Transition script'
    }
    if ($UseTested -and $sha -ne $AudioTransition.Tested.Sha256) {
        Remove-Item -LiteralPath $partial
        throw "checksum mismatch for the tested version (got $sha, expected $($AudioTransition.Tested.Sha256))"
    }
    $version = Get-AudioTransitionVersion $text
    $folder  = Join-Path $InstallerDir "$($AudioTransition.Name) $version"
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    Move-Item -LiteralPath $partial -Destination (Join-Path $folder 'audio-transition.zip') -Force
    return @{ Bytes = $bytes; Version = $version; IsTested = ($sha -eq $AudioTransition.Tested.Sha256) }
}

# The latest release (or the tested one with -Tested); falls back to the tested
# one, and returns $null if neither can be downloaded.
function Resolve-AudioTransition {
    if (-not $script:Tested) {
        try { return Get-AudioTransitionRelease $false }
        catch { Write-Note "$($AudioTransition.Name): could not get the latest version ($($_.Exception.Message)). Trying the last tested version, $($AudioTransition.Tested.Version)." }
    }
    try { return Get-AudioTransitionRelease $true }
    catch { Write-Note "$($AudioTransition.Name): could not get the tested version either ($($_.Exception.Message))." }
    return $null
}

# --- Download-only mode -----------------------------------------------------
if ($DownloadOnly) {
    $which = if ($Tested) { 'last tested' } else { 'latest' }
    Write-Step "Downloading the $which installers into $InstallerDir"
    $obsMajor = ''
    foreach ($d in $Dependencies) {
        $target = Resolve-Target $d $obsMajor
        if ($d.Name -eq 'OBS Studio') { $obsMajor = ($target.Version -split '\.')[0] }
        if ($target.Version -ne $d.Tested.Version) { Write-Note "$($d.Name) $($target.Version): WARNING: not tested with this setup yet (last tested: $($d.Tested.Version))." }
        Save-Installer $d $target | Out-Null
    }
    Save-Installer $Python ($Python.Tested + @{ Latest = $false }) | Out-Null
    $at = Get-AudioTransitionRelease $Tested.IsPresent
    $atNote = if ($at.IsTested) { 'tested' } else { "WARNING: not tested with this setup yet (last tested: $($AudioTransition.Tested.Version))" }
    Write-Ok "$($AudioTransition.Name) $($at.Version): downloaded ($atNote)."
    Write-Host ''
    Write-Host 'Done. Nothing was installed.' -ForegroundColor Cyan
    exit 0
}

# --- 0. Preconditions -------------------------------------------------------
Write-Step 'Checking preconditions'

if (Get-Process -Name obs64, obs32 -ErrorAction SilentlyContinue) {
    throw 'OBS is running. Close OBS and run this again.'
}

# --- Elevated run: install dependencies only --------------------------------
if ($DependenciesOnly) {
    Write-Step 'Installing OBS, VLC and plugins (admin)'
    foreach ($item in @(Get-DependencyPlan $false)) { Install-Dependency $item }
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
    $plan = @(Get-DependencyPlan $false)
    if ($plan.Count -gt 0) {
        if (Test-Admin) {
            foreach ($item in $plan) { Install-Dependency $item }
        } else {
            Write-Host "    Installing $($plan.Count) program(s) needs admin rights. Windows will ask for permission..."
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -DependenciesOnly"
            if ($Upgrade) { $argList += ' -Upgrade' }
            if ($Tested)  { $argList += ' -Tested' }
            try {
                $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
            } catch {
                throw 'Admin permission was refused, so OBS, VLC and the plugins were not installed. Run again to retry, or use -SkipDependencies.'
            }
            if ($p.ExitCode -ne 0) { throw "Installing the dependencies failed (exit code $($p.ExitCode)). See the admin window's message." }
        }
        $still = @(Get-DependencyPlan $true)
        if ($still.Count -gt 0) { throw "Not installed as expected after running the installers: $(($still | ForEach-Object { $_.Dep.Name }) -join ', ')" }
        Write-Ok 'OBS, VLC and plugins are in place.'
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

# Audio Transition script: not part of this repo, downloaded from the OBS forum.
$atLocal        = if (Test-Path -LiteralPath $AudioTransitionDest) { Read-Text $AudioTransitionDest } else { $null }
$atLocalVersion = if ($atLocal) { Get-AudioTransitionVersion $atLocal } else { $null }
$atRelease      = Resolve-AudioTransition
if (-not $atRelease) {
    if ($atLocal) { Write-Note "$($AudioTransition.Name) $atLocalVersion kept as is (could not check for a newer version)." }
    else { Write-Note "$($AudioTransition.Name) is missing: download it from $($AudioTransition.Page) and save audio-transition.lua in Scripts\." }
} else {
    $atKind = if ($Tested) { 'tested' } else { 'latest' }
    $atWarn = if (-not $atRelease.IsTested) { " WARNING: not tested with this setup yet (last tested: $($AudioTransition.Tested.Version))." } else { '' }
    if (-not $atLocal) {
        [IO.File]::WriteAllBytes($AudioTransitionDest, $atRelease.Bytes)
        Write-Ok "$($AudioTransition.Name) $($atRelease.Version) ($atKind) downloaded into Scripts\.$atWarn"
    } elseif ((Compare-Version $atLocalVersion $atRelease.Version) -lt 0) {
        if ($Upgrade) {
            Copy-Item -LiteralPath $AudioTransitionDest -Destination "$AudioTransitionDest.before-install-$Stamp"
            [IO.File]::WriteAllBytes($AudioTransitionDest, $atRelease.Bytes)
            Write-Note "$($AudioTransition.Name) upgraded from $atLocalVersion to $($atRelease.Version) ($atKind); the old file was backed up.$atWarn"
        } else {
            Write-Note "$($AudioTransition.Name) $atLocalVersion present. Newer $atKind version $($atRelease.Version) is available. Run install.bat -Upgrade to install it."
        }
    } else {
        Write-Ok "$($AudioTransition.Name) $atLocalVersion present."
    }
}

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
    } elseif (-not (Test-Path -LiteralPath $FontSrc)) {
        Write-Note "$fontName is not installed and not in Fonts\ (it isn't part of this repo). The title and end-text overlays will use a substitute font until you install it: see 'Recommended font' in README.md."
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
    $requirementsChanged = $false

    # Clone the latest main, or bring an existing clone up to date when that's safe.
    if (Test-Path -LiteralPath $TickersDir) {
        if (-not (Test-Path -LiteralPath (Join-Path $TickersDir '.git'))) {
            Write-Note "$tickersRel is not a git clone. Not updated."
        } elseif (-not $haveGit) {
            Write-Note 'git not found. The tickers were not checked for updates.'
        } else {
            $requirementsChanged = Update-TickersClone $tickersRel
        }
    } else {
        if (-not $haveGit) { throw 'git is needed to download the live tickers. Install Git for Windows, or use -SkipTickers.' }
        Write-Host "    Cloning the latest $TickersBranch of $TickersUrl..."
        Invoke-Git clone --quiet --branch $TickersBranch $TickersUrl $tickersRel | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $TickersDir 'setup.bat'))) {
            throw "Could not clone the live tickers from $TickersUrl (exit code $LASTEXITCODE)."
        }
        Write-Ok "Cloned into $tickersRel ($(Invoke-GitIn $TickersDir describe --tags --always))."
    }

    # Virtual environment via the tickers' own setup.bat: when it's missing, or
    # when requirements.txt changed in the update (setup.bat reuses .venv then).
    if ((Test-Path -LiteralPath $tickersVenv) -and -not $requirementsChanged) {
        Write-Ok 'Python environment already set up.'
    } else {
        $py = Find-Python $Python.Minor
        if (-not $py) {
            Write-Host "    Python $($Python.Tested.Version) not found, installing it for the current user..."
            $file = Save-Installer $Python ($Python.Tested + @{ Latest = $false })
            $p = Start-Process -FilePath $file -ArgumentList $Python.Args -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "Python installer failed (exit code $($p.ExitCode))." }
            $py = Find-Python $Python.Minor
            if (-not $py) { throw "Python $($Python.Tested.Version) was installed but could not be found." }
            Write-Ok "Python $($py.Version) installed."
        } elseif ($py.Version -ne $Python.Tested.Version) {
            Write-Note "Using Python $($py.Version) (this repo pins $($Python.Tested.Version))."
        } else {
            Write-Ok "Python $($py.Version) found."
        }

        # Put this Python first on PATH for setup.bat. The empty input answers its
        # final 'pause'. '.\' because some PCs block running files from the current
        # folder by bare name (NoDefaultCurrentDirectoryInExePath).
        $why = if ($requirementsChanged) { 'requirements.txt changed, updating packages' } else { 'creates .venv, installs packages' }
        Write-Host "    Running the tickers' setup.bat ($why)..."
        $pyDir = Split-Path $py.Exe -Parent
        $previousPath = $env:Path
        $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
        Push-Location -LiteralPath $TickersDir
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try     { '' | & cmd.exe /d /c .\setup.bat | ForEach-Object { "      $_" } | Write-Host }
        finally { $ErrorActionPreference = $prev; Pop-Location; $env:Path = $previousPath }

        # setup.bat always exits 0, so the import check below is what decides.
        if (-not (Test-Path -LiteralPath $tickersVenv)) { throw 'setup.bat did not create the .venv folder.' }
        Write-Ok 'Python environment ready.'
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
