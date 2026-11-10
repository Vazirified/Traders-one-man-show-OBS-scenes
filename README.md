# Traders one-man show OBS scenes

A complete OBS Studio setup for running a live trading show on your own: one
presenter, one PC, streaming in **landscape (16:9) and portrait (9:16) at the
same time**. It includes the scenes, overlays, scripts, live market tickers and
one installer that puts it all in place on a Windows PC.

- **Dual output**: every scene exists as a landscape (`H`) and a portrait (`V`)
  version. The portrait canvas comes from the Aitum Vertical plugin.
- **Scenes**: Background and Title, Background Only, Camera Only, Screen and
  Camera, Screen Only, Background and End Text, and Viola.
- **Camera options**: webcam, a phone through DroidCam, or a remote camera
  through VDO.Ninja, with face tracking and a rounded-corner mask.
- **Zoom to mouse**: zooms the screen capture to follow your mouse pointer,
  with a zoom area that matches the portrait or landscape frame.
- **Live tickers**: market prices from MetaTrader 5, shown as browser overlays
  ([live-tickers](https://github.com/Vazirified/live-tickers), a separate project).
- **Smooth changes**: Move and Stinger transitions, and audio that mutes,
  unmutes or fades as scenes change (Audio Transition script).

---

## Installation

### What you need

| Need | Why |
|---|---|
| Windows 10 or 11, 64-bit | OBS, the plugins and the installer are Windows builds. |
| [Git for Windows](https://git-scm.com/download/win), which includes Git LFS | To download this repo and the live tickers. Artwork and the font are stored with Git LFS. |
| An internet connection | The installer downloads OBS, VLC, the plugins, Python and the tickers' packages. |
| Admin rights on the PC | Only for installing programs. Windows asks once. |
| MetaTrader 5 from your broker, logged in | The tickers read prices from it. Not installed for you (see below). |

You don't need to install OBS, the plugins or Python yourself. The installer
does that.

### Steps

1. **Close OBS** if it's running.

2. **Download the repo** to any folder you like, for example your Documents:

   ```bash
   git clone https://github.com/Vazirified/Traders-one-man-show-OBS-scenes.git
   ```

   Keep it there afterwards. OBS will load the scripts and images from this
   folder. If you move it later, run the installer again.

3. **Run the installer**: double-click **`install.bat`** in that folder.

   - When programs need installing, Windows asks for admin permission (UAC)
     and a second window shows the installs. Your own window continues when
     it's done.
   - When asked, enter your **VDO.Ninja stream ID** (the `v=` value of your
     VDO.Ninja link). Leave it blank to skip; the VDO.Ninja camera then stays
     empty until you set it in OBS.
   - Read the yellow lines at the end: they list anything you still need to do.

4. **Add the music** (not included, see [What's not in this repo](#whats-not-in-this-repo)).
   Optionally install the [recommended font](#recommended-font).

5. **Before going live**: start MetaTrader 5 and log in, run
   `Scripts\live-tickers-v.2.0\run.bat`, then start OBS.

6. **First time on a new PC**, in OBS:
   - Pick your own camera, microphone and screen in the **Webcam**,
     **External Microphone Capture**, **Audio Input Capture**, **Main Display
     Capture** and **Zoomable Display Capture** sources. Device choices are
     saved per PC, so they won't match a different computer.
   - Set up your stream service and keys under **Settings > Stream** (they
     are deliberately not in this repo), and the vertical stream in the Aitum
     Vertical dock.
   - Assign hotkeys for **Toggle zoom to mouse** and **Toggle follow mouse
     during zoom** under **Settings > Hotkeys**.

### What the installer does

`install.bat` runs `install.ps1` with PowerShell. It works through these steps
in order and prints what it did for each one. It's safe to run again at any
time: anything already in place is left alone.

| Step | What happens |
|---|---|
| **0. Checks** | Stops if OBS is running. Warns if OBS keeps its settings in a custom location. |
| **1. OBS, VLC and plugins** | Looks up the **latest release** of each program (table below) and compares it with what's installed. Missing programs are installed. Installed ones are left alone; if a newer version exists it tells you, and `-Upgrade` installs it. Installing anything newer than the version this setup was last tested with prints a **WARNING**. |
| **2. VDO.Ninja ID** | Stores your stream ID in this repo's local git settings (never uploaded). Sets up a git filter that swaps the ID for a placeholder in every commit. |
| **3. Scene collection and scripts** | Copies the scene collection into OBS, with every file path changed to wherever you downloaded the repo. The two Lua scripts and their settings are part of the scene collection, so they're installed with it. Downloads the latest [Audio Transition](https://obsproject.com/forum/resources/audio-transition.2117/) script from the OBS forum into `Scripts\` (it isn't part of this repo); an existing copy is only replaced with `-Upgrade`. |
| **4. Active collection** | Makes this scene collection the one OBS opens with. |
| **5. Aitum Vertical settings** | Installs the portrait canvas settings, with recordings going to your own Videos folder. |
| **6. Font** | If the [recommended font](#recommended-font) isn't installed yet and you've put `IRZar.ttf` in the `Fonts` folder, installs it for your Windows account (no admin needed). Otherwise it reminds you. |
| **7. Live tickers** | Downloads the latest [live-tickers](https://github.com/Vazirified/live-tickers) (`main` branch) into `Scripts\live-tickers-v.2.0`, or updates an existing copy. Installs Python 3.14.2 for your account if it's missing, runs the tickers' own `setup.bat`, and checks that their packages load. Tells you if MetaTrader 5 is missing. |
| **8. Media check** | Lists any file the scenes use that isn't on the PC, such as the music. |

#### Programs it installs

| Program | Source | Last tested version |
|---|---|---|
| OBS Studio | github.com/obsproject/obs-studio | 33.0.1 |
| VLC media player (for the background music source) | download.videolan.org | 3.0.23 |
| DroidCam OBS plugin | github.com/dev47apps/droidcam-obs-plugin | 2.5.1 |
| Move Transition | github.com/exeldro/obs-move-transition | 3.2.1 |
| Aitum Vertical | github.com/Aitum/obs-vertical-canvas | 1.6.1 |
| Face Tracker | github.com/norihiro/obs-face-tracker | 0.9.0 |
| Python (for the tickers, installed for your account only) | python.org | 3.14.2 (always this version) |
| [Audio Transition](https://obsproject.com/forum/resources/audio-transition.2117/) script by dqm | obsproject.com forum | 1.1 |

Python stays at 3.14.2 because the MetaTrader 5 Python package only works with
particular Python versions.

#### How downloads are checked

Every installer goes into the `installers` folder and is only run if both
checks pass:

1. **Checksum**: its SHA-256 matches the one the publisher lists for that
   release (GitHub's release page, or the `.sha256` file VideoLAN publishes).
   The last tested versions have their checksums written in `install.ps1`.
2. **Signature**: it has a valid code signature from the expected publisher
   (OBS Project, VideoLAN, DEV47 APPS, Exeldro, Aitum, Norihiro Kamae, Python
   Software Foundation).

A file that fails either check is deleted and nothing is installed. Installers
are run silently with their official options.

The Audio Transition script is the exception: it's a plain Lua script in a zip,
with no published checksum or signature. The installer only takes
`audio-transition.lua` from the zip, checks that it is that script, and warns
when it differs from the tested version (whose SHA-256 is recorded in
`install.ps1`). You can read the script in `Scripts\` before starting OBS.

#### What it never does

- **Change a working setup without asking.** Installed programs are only
  upgraded with `-Upgrade`, and never downgraded. If the scene collection or
  vertical settings in OBS differ from the repo, it stops; `-Force` replaces
  them after saving a backup (`*.before-install-<date-time>`).
- **Overwrite your tickers work.** An existing tickers folder is only updated
  when it's a clean copy of `main`. Local edits, another branch, or commits
  that aren't on GitHub yet: it tells you and leaves the folder alone.
- **Touch your stream keys.** They live in your OBS profile, which this repo
  doesn't include.

### Installer options

Add options after `install.bat`, for example `install.bat -Upgrade`.

| Option | What it does |
|---|---|
| `-Upgrade` | Also upgrade installed programs and the Audio Transition script when a newer release exists. |
| `-Tested` | Use the last tested versions instead of the latest (for new installs and `-Upgrade`). Useful when a new release causes problems. |
| `-Force` | Replace the scene collection and vertical settings in OBS even if they differ from the repo (the old files are backed up first). |
| `-DownloadOnly` | Only download and check the installers into `installers`, for example to keep an offline copy. Installs nothing. Combine with `-Tested` for the tested versions. |
| `-VdoNinjaId <id>` | Give the VDO.Ninja stream ID without being asked. |
| `-SkipDependencies` | Don't check or install OBS, VLC and the plugins. |
| `-SkipTickers` | Don't set up or update the live tickers. |
| `-SkipFont` | Don't install the font. |
| `-ObsConfigDir <folder>` | Use a different OBS settings folder (default `%APPDATA%\obs-studio`). |

### If the installer stops

It prints one red `STOPPED:` line with the reason. The common ones:

| Message | What to do |
|---|---|
| OBS is running | Close OBS and run it again. |
| Scene collection ... differs from the repo | You changed the scenes in OBS since the last install. Run `install.bat -Force` to replace them (a backup is kept), or copy your changes into the repo first (see [Keeping the repo up to date](#keeping-the-repo-up-to-date)). |
| Admin permission was refused | Run it again and choose Yes, or use `-SkipDependencies` and install the programs yourself. |
| Checksum mismatch, or signature not valid | The download was damaged or isn't the publisher's file. It was deleted, not run. Try again later, or use `-Tested`. |
| Could not look up the latest release / reach GitHub | Without internet, programs fall back to the last tested versions (already downloaded ones are reused from `installers`), and an existing tickers folder is kept as it is. A first-time tickers download needs GitHub: check your connection. |

---

## What's not in this repo

| Missing | Why | What to do |
|---|---|---|
| Background music (`resources/live-session-music/`) and `opening_bell.wav` | They're from the YouTube Audio Library, which allows using them in videos but not sharing the files. | Download the tracks below from the YouTube Audio Library (YouTube Studio > Audio Library) into `VazirifiedFX-dual-output-scene\resources\live-session-music\`, and add an `opening_bell.wav` to `VazirifiedFX-dual-output-scene\resources\`. |
| Audio Transition script (`Scripts/audio-transition.lua`) | It's dqm's script, published on the OBS forum without a license to share it. | The installer downloads it. |
| IRZar font (`Fonts/IRZar.ttf`) | It's a recommendation rather than part of the setup. | See [Recommended font](#recommended-font). |
| MetaTrader 5 | It's your broker's build and needs your login. | Install your broker's MetaTrader 5 and log in. |
| OBS profile (stream service, keys, output and hotkey settings) | It holds your stream keys. | Set them up in OBS once per PC. |
| VDO.Ninja stream ID | Anyone with it could watch or send to your feed. | The installer asks for it; it's kept only on your PC. |
| Live tickers | They're their own project. | The installer downloads them. |

<details>
<summary>Music tracks (58, all from the YouTube Audio Library)</summary>

| Title | Artist |
|---|---|
| Akatsuki Rising | The Mini Vandals |
| Alpha Mission | Jimena Contreras |
| Aomori Wings | The Mini Vandals |
| Atlantis Rage | Jimena Contreras |
| Blue Screen Of Death | The Soundlings |
| Broken Promise | Jimena Contreras |
| CAVERNS | Density & Time |
| Como Vamos | Casa Rosa |
| Dead Wrong | Jeremy Blake |
| Deep Space Sector 9 | Ezra Lipp |
| Deified | The Grey Room / Density & Time |
| Devious Little Smile | Godmode |
| Distrust The System | The Soundlings |
| Drifting Memories | The Mini Vandals |
| Fact or Friction | The Soundlings |
| Final Girl | Jeremy Blake |
| Future Rennaisance | Godmode |
| Galactic Bass | John Patitucci |
| Heartbeat | Godmode |
| Heartbeat Of The Wind | Asher Fulero |
| Helium | TrackTribe |
| Hypnosis | Godmode |
| Keep Climbing | The Soundings |
| Lake Jupiter | John Patitucci |
| Level | The Grey Room / Density & Time |
| Long Goodbyes to Longer Friends | Schwartzy |
| Love's Aftermath | Asher Fulero |
| Midnight Trace | Jimena Contreras |
| Missing Persons | Jeremy Blake |
| Moonlight Magic | Asher Fulero |
| Moving In The Shadows | The Soundlings |
| Pienso Viento | Casa Rosa |
| Radar | The Grey Room / Density & Time |
| Radio Flyer | Nathan Moore |
| Rain Over Kyoto Station | The Mini Vandals |
| Red Shift | The Grey Room / Density & Time |
| Reviver | The Grey Room / Density & Time |
| Rogue Force | Jimena Contreras |
| Sagas | The Grey Room / Density & Time |
| Shadow Chase | Jimena Contreras |
| Shady Guise | The Soundlings |
| Sleep Music No. 1 | Chris Haugen |
| Somnia Variation 1 (relax and sleep) | Reed Mathis |
| Somnia Variation 2 (relax and sleep) | Reed Mathis |
| Somnia Variation 3 (relax and sleep) | Reed Mathis |
| Somnia Variation 8 (relax and sleep) | Reed Mathis |
| Somnia Variation 9 (relax and sleep) | Reed Mathis |
| Somnia Variation 10 (relax and sleep) | Reed Mathis |
| Splinters Lair | Ezra Lipp |
| Standoff | Density & Time |
| System Corruption | The Soundlings |
| Taking Chances | The Soundings |
| The Journey Ahead | Ezra Lipp |
| The Palace Gardens | Asher Fulero |
| The Road To Mordor | Ezra Lipp |
| Tiburtina | Schwartzy |
| TORSION | Density & Time |
| Viral Dirge | Ryan Stasik |

The background music source plays every file in the folder, so you can use
any tracks you're allowed to use.

</details>

### Recommended font

The **Title** and **End Text** overlays are designed for **IRZar**, a Persian
typeface from the Information Technology Organization of Iran
([ito.gov.ir](https://ito.gov.ir)), licensed under the
[SIL Open Font License 1.1](https://openfontlicense.org). Without it, OBS shows
those texts in a substitute font.

To use it, either:

- put `IRZar.ttf` in the `Fonts` folder and run `install.bat` (it installs the
  font for your Windows account), or
- right-click `IRZar.ttf` and choose **Install**, then restart OBS.

Any other font works too: pick it in those text sources' properties.

---

## What's in this repo

```text
install.bat                      Double-click to install (runs install.ps1)
install.ps1                      The installer
VazirifiedFX-dual-output-scene/
  VazirifiedFX-dual-output-scene-collection.json   The OBS scene collection
  vertical-canvas-config.json                      Aitum Vertical settings
  resources/                     Backgrounds, camera mask and their design files
Scripts/
  variable-ratio-obs-zoom-to-mouse.lua   Zoom to mouse, any aspect ratio
  audio-transition.lua           Audio fades between scenes (downloaded by the installer, not part of this repo)
  live-tickers-v.2.0/            Live tickers (downloaded by the installer, not part of this repo)
Fonts/                           Put IRZar.ttf here (recommended font, not part of this repo)
Settings/                        Screenshots of the zoom and face tracker settings
tools/vdoninja-filter.sh         Keeps the VDO.Ninja ID out of commits
installers/                      Downloaded installers (not part of this repo)
```

---

## Keeping the repo up to date

These notes are for whoever maintains the setup.

**After changing scenes in OBS**, close OBS and copy its files into the repo,
then commit:

```bat
copy "%APPDATA%\obs-studio\basic\scenes\Double_Output_Vazirified_Channels.json" "VazirifiedFX-dual-output-scene\VazirifiedFX-dual-output-scene-collection.json"
copy "%APPDATA%\obs-studio\plugin_config\vertical-canvas\config.json" "VazirifiedFX-dual-output-scene\vertical-canvas-config.json"
```

The file paths inside can point to any folder: the installer works out where
the scene was saved from and rewrites them.

**After testing a newer program version**, open `install.ps1`, find that
program in the `$Dependencies` list, and copy the new release's version,
download link and SHA-256 into its `Tested` block. Commit that together with
the scene files, so every commit is a set that's known to work together.

**Live tickers** are developed in their own repo. The installer always uses
the latest `main`, so pushing to `main` there updates every PC on its next
install. Push work in progress to another branch.

**The VDO.Ninja ID** never reaches a commit: the filter in
`tools/vdoninja-filter.sh` replaces it with `__VDO_NINJA_STREAM_ID__` and puts
it back when files are checked out. The ID itself is stored only in this PC's
`.git/config`. On a new PC the installer sets this up; don't commit a scene
file on a PC where the installer hasn't run.

---

## Credits

- [OBS Studio](https://obsproject.com/)
- [Move Transition](https://github.com/exeldro/obs-move-transition) by Exeldro
- [Aitum Vertical](https://github.com/Aitum/obs-vertical-canvas) by Aitum
- [Face Tracker](https://github.com/norihiro/obs-face-tracker) by Norihiro Kamae
- [DroidCam OBS plugin](https://github.com/dev47apps/droidcam-obs-plugin) by DEV47 APPS
- [VDO.Ninja](https://vdo.ninja/) for the remote camera
- `variable-ratio-obs-zoom-to-mouse.lua`: by Vazirified, inspired by
  [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) by BlankSourceCode
- [Audio Transition](https://obsproject.com/forum/resources/audio-transition.2117/) script by dqm
  (downloaded by the installer)
- IRZar font: Information Technology Organization of Iran (recommended, not included)
- Music: YouTube Audio Library (not included)
