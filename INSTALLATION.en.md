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

## Control Center

Open **Jellyfin VLC Bridge** from the Windows Start menu. It immediately checks
Jellyfin, VLC and the Chrome/Edge integration.

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
local `jellyfin-vlc` protocol and the Windows uninstall entry for the current
user. It does not add a desktop shortcut.

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
