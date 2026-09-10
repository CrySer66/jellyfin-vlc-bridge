# Installation guide

[Documentation française](INSTALLATION.md)

## Requirements

- Windows 10 or Windows 11, 64-bit;
- VLC Media Player;
- Google Chrome;
- a Jellyfin server reachable from the PC;
- Quick Connect enabled in Jellyfin.

The required .NET runtime is included with the application. VLC and the Chrome
extension are the only separate components to install.

## Install the Bridge

1. Download `JellyfinVlcBridge-<version>-Setup.exe` from the
   [latest GitHub Release](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest).
2. Run the installer.
3. Enter the Jellyfin server address, for example `http://192.168.1.25:8096`.
4. The installer displays a temporary Quick Connect code.
5. In Jellyfin, open **Settings → Quick Connect**, enter the code and approve it.
6. Wait for the **Installation completed successfully** message.

Installing a newer version over an existing installation keeps the Jellyfin
connection and displays the saved server address. Select **Change Jellyfin
server** only when you intentionally want to remove the old connection and start
a new Quick Connect session.

## Install with WinGet (optional)

Version 1.18.0 was [accepted into the WinGet community repository on August 31, 2026](https://github.com/microsoft/winget-pkgs/pull/413912). During our check that day, the refreshed catalog did not offer it yet. There is no need to uninstall the Bridge or change your configuration.

In PowerShell or Windows Terminal, check availability first without installing anything:

```powershell
winget source update --name winget
winget show --id CrySer66.JellyfinVlcBridge --exact --source winget
```

If WinGet reports **No package found matching input criteria**, try again later or use the GitHub installer above. If the `winget` command is missing, see the [Microsoft guide](https://learn.microsoft.com/windows/package-manager/winget/) or use the standard installer. Do not disable security checks or reset sources to work around the wait.

Once the listing is available, install the Bridge with:

```powershell
winget install --id CrySer66.JellyfinVlcBridge --exact --source winget --silent
```

This uses the same official installer hosted on GitHub. WinGet verifies its hash, and the manifest declares **VideoLAN.VLC** as a dependency. Installing VLC may require administrator approval; the Bridge itself is installed for the current user. Read any agreement prompts displayed by WinGet.

Silent installation does not open a browser or a connection window. Once it finishes:

1. Open **Jellyfin VLC Bridge** from the Start menu and connect your server using **Quick Connect**.
2. Install the [official Chrome extension](https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp) separately.
3. Reload Jellyfin and try **Play with VLC** on a movie or episode.

For a future update available in WinGet, close the Control Center and finish any active playback, then run:

```powershell
winget upgrade --id CrySer66.JellyfinVlcBridge --exact --source winget --silent
```

Your Quick Connect token and settings are preserved. WinGet versions may arrive after GitHub Releases, so **no available upgrade** is not necessarily an error. The Control Center's built-in updater remains usable; do not run both update methods at the same time.

To uninstall, use **Windows Settings → Apps → Jellyfin VLC Bridge**, as described below. WinGet does not replace Chrome's extension management or an Authenticode signature, and does not guarantee that SmartScreen warnings disappear.

Microsoft references: [installation](https://learn.microsoft.com/windows/package-manager/winget/install), [upgrades](https://learn.microsoft.com/windows/package-manager/winget/upgrade).

## Control Center

Open **Jellyfin VLC Bridge** from the Windows Start menu. It immediately checks
Jellyfin, VLC and the Chrome/Edge integration.

After installation, a Jellyfin VLC Bridge icon starts quietly in the Windows
notification area. **Minimize** keeps the window in the taskbar, while **Close**
hides it near the clock. Double-click the icon to reopen the Control Center; its
menu can also refresh diagnostics or
quit the icon until the next Windows sign-in. Playback from the extension remains
available even when the notification icon has been closed.

- **Repair browser** registers the local communication with the extension again;
- **Playback settings** selects HTTP Direct Play or SMB and the VLC executable;
- **Copy a diagnostic without secrets** copies useful version and status
  information without a token or user identifier;
- **Create support package** saves a ZIP containing the diagnostic and recent
  redacted logs, ready to attach to a GitHub Issue;
- **Help and report a bug** opens the official guides and support forms.

When a check fails, the corresponding card explains the likely cause and
suggests the next action. Support packages automatically remove tokens, Jellyfin
identifiers, server addresses and personal Windows paths.

## Install the Chrome extension

The Chrome Web Store page opens automatically when installation finishes. Select
**Add to Chrome**, then confirm.

If that page was closed, open the official listing:

https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp

Chrome automatically installs extension updates after Google has reviewed them.
Selecting the extension icon shows whether the Windows Bridge is ready and
provides links to the download, GitHub repository and support page.

When the Windows application is missing, Jellyfin displays **Application not
installed** instead of **Play with VLC**. Select that action to open the official
download.

## First playback

1. Reload the Jellyfin page.
2. Open a movie, episode, season, show or collection.
3. Select **Play with VLC**.
4. Choose whether to resume or restart and, for grouped content, which items to
   include.
5. Select **Launch in VLC**.

The Bridge works silently in the background. Shows and collections are prepared
as VLC playlists so the next item can start in the same VLC window.

## Playback modes

**HTTP Direct Play** is recommended. Jellyfin sends the original media to a local
authenticated relay and VLC reads it without video transcoding.

**SMB** lets VLC open an existing Windows network share directly. Use it only
when that share already works in File Explorer, then configure the server-folder
to client-share mapping in the Control Center.

## Updates

The Control Center checks the latest official Release from
`CrySer66/jellyfin-vlc-bridge`. When an update is available, select **Install**.
The installer replaces the application files while preserving the Quick Connect
token, configuration and playback preferences.

The Chrome extension is updated separately and automatically by the Chrome Web
Store.

### After upgrading to Jellyfin 12

1. Install Bridge **1.18.1 or later** over the existing installation. The connection and settings are preserved.
2. Check the extension version in `chrome://extensions`: **1.8.1 or later** displays preparation errors in the playback dialog. Its Chrome Web Store rollout is independent of the Bridge release.
3. Fully reload existing Jellyfin tabs with **Ctrl+Shift+R**, then open a movie or episode and select **Play with VLC**.

If the dialog still reports an authentication failure, open the Control Center and refresh diagnostics. Repeat Quick Connect only if diagnostics ask you to reconnect the server. See the [compatibility guide](docs/COMPATIBILITY.md#jellyfin-10x-and-12) for checks of older and newer versions.

## Automated installation (advanced)

The Setup accepts `/quiet` for package managers and unattended deployments:

```powershell
.\JellyfinVlcBridge-<version>-Setup.exe /quiet
```

This mode installs the files and Windows integration without opening Chrome,
the Control Center or Quick Connect. On first use, open **Jellyfin VLC Bridge**
from the Start menu and connect the server through Quick Connect. An existing
connection is preserved during an update.

The `/silent`, `/S`, `--quiet` and `--silent` aliases are also accepted.
Unattended removal uses the Windows `QuietUninstallString` and keeps the
connection by default. The uninstaller script's technical `-Silent -Purge`
option also removes the configuration and token.

## Uninstall

Open:

```text
Windows Settings → Apps → Installed apps → Jellyfin VLC Bridge
```

The uninstaller offers two choices:

- **Keep the connection** for a future reinstallation;
- **Delete everything** to remove the Jellyfin configuration and token as well.

Chrome manages the extension separately. Remove it from `chrome://extensions`.

## Files and Windows integration

Application:

```text
%LOCALAPPDATA%\JellyfinVlcBridge\App
```

Non-secret configuration:

```text
%LOCALAPPDATA%\JellyfinVlcBridge\config.json
```

The Quick Connect token is protected by Windows Credential Manager. It is never
stored in the extension, repository or configuration file.

The installer registers the native-messaging connection for Chrome and Edge, the
local `jellyfin-vlc` protocol, the notification-area startup entry and the
Windows uninstall entry for the current user. It does not add a desktop
shortcut.

## Quick troubleshooting

### The button does not appear

- confirm that the extension is installed and enabled in `chrome://extensions`;
- fully reload Jellyfin;
- open a media page that has a playback action.

### VLC does not start

- confirm that VLC is installed;
- open the Bridge Control Center;
- select **Repair**, then **Refresh**.

### Quick Connect does not work

- verify the server address;
- enable Quick Connect in Jellyfin administration;
- confirm that the PC can open Jellyfin in its browser.

### SmartScreen or antivirus warning

The source is public, but the installer is not yet signed with a commercial code
signing certificate. Download it only from the official GitHub Releases page.
