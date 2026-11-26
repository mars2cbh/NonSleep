# NonSleep

[English](README.md) | [한국어](README.ko.md)

**Running AI on your MacBook?**

Keep your AI jobs running with NonSleep, even with the lid closed.

A macOS menu bar app with three independent controls: keep your Mac awake, stay awake with the lid closed, and enable Do Not Disturb. Built with SwiftUI, with Sparkle 2 for update installation. Requires macOS 14 or later.

## Install with a DMG

New releases include disk images for Apple Silicon and Intel. Download the `.dmg` for your Mac from [GitHub Releases](https://github.com/mars2cbh/NonSleep/releases): `arm64` for Apple Silicon, or `x86_64` for Intel.

1. Open the DMG. NonSleep and the Applications folder appear side by side.
2. Drag **NonSleep.app → Applications** to install it.
3. Eject the disk image and launch NonSleep from Applications.

The installer background includes both English and Korean instructions. ZIPs are also provided for in-app updates and manual extraction.

## Build and run

Use Xcode 16.4 or later, or the corresponding Swift toolchain. Run these commands from the project directory:

```sh
./scripts/build.sh
open build/NonSleep.app
```

The app bundle is created at `build/NonSleep.app`. You can also copy it to Applications. A coffee cup appears in the menu bar when the app launches. Click it to open the three switches, or right-click for quick controls. The cup fills in when a feature is active. Clicking outside the dashboard closes it while the app continues running in the menu bar. Open `Package.swift` in Xcode to work on the source, and use the script above to create the app bundle.

The menu bar icon changes color based on the active features. Hover over it to see which features are enabled.

| Active features | Icon color |
| --- | --- |
| All off | Gray |
| Keep Awake | Green |
| Stay Awake with Lid Closed | Blue |
| Do Not Disturb | Purple |
| Keep Awake + Stay Awake with Lid Closed | Cyan |
| Keep Awake + Do Not Disturb | Orange |
| Stay Awake with Lid Closed + Do Not Disturb | Pink |
| All three | Yellow |

Run the development tests:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path "$PWD/.build/cache"
```

## Features and initial setup

| Control | Behavior | Initial setup |
| --- | --- | --- |
| Keep Awake | Uses IOKit assertions to prevent idle system sleep and display sleep | None |
| Stay Awake with Lid Closed | Applies `pmset -a disablesleep 1` and verifies the setting | Register the power helper once in Settings, or authenticate each time you toggle the feature |
| Do Not Disturb | Runs linked Apple shortcuts to turn Focus on or off | Connect the two shortcuts described below |

### Global hotkeys

Use these shortcuts from any app while NonSleep is running:

| Action | Default hotkey |
| --- | --- |
| Toggle Keep Awake | `⌃⌥⌘1` |
| Toggle Stay Awake with Lid Closed | `⌃⌥⌘2` |
| Toggle Do Not Disturb | `⌃⌥⌘3` |

Open **Settings → Hotkeys** to enable or disable global hotkeys, record a different combination for each feature, clear a binding, or restore the defaults. Include Control (`⌃`) or Option (`⌥`) in custom combinations. Escape cancels recording; Delete clears a binding. Changes persist across restarts. A shortcut that conflicts with another app is reported without disabling the other features.

Closed-lid mode still uses the existing administrator permissions. Connect the On and Off shortcuts in the Do Not Disturb tab before using its hotkey. If it is not configured, the hotkey opens setup. The switch continues to show the last successful shortcut request rather than the actual macOS Focus state.

### English and Korean

The app follows your macOS language preferences by default. It uses Korean when Korean is the preferred supported language, English when English is preferred, and English if neither language is supported by your preferences.

Choose **Follow System Settings / English / 한국어** in **Settings → General → Language**. The dashboard, settings, menus, and app messages change immediately, and your choice survives app restarts. Sparkle update dialogs use the selected language after restarting the app. macOS authentication dialogs and other apps follow the system language settings.

Translations are in `Sources/NonSleepCore/Resources/en.lproj/Localizable.strings` and `ko.lproj/Localizable.strings`. Release bundles include these resources.

### Launch at login and administrator access

Open the coffee cup menu → **Settings → General**. You can also use **Settings…** in the right-click menu or press `⌘,`.

Settings opens in its own window, separate from the menu bar popover. The dashboard switches and buttons remain usable after closing Settings or switching to another app.

- **Launch at login**: Registers or unregisters the app through macOS `SMAppService.mainApp`. The displayed status reflects the actual system registration. If macOS requires approval, use **Open Login Items** to review it. Move the app to Applications before enabling this option.
- **Closed-Lid Permission → Authorize Helper…**: Approve installation of the power helper in the macOS administrator authentication dialog. After registration, feature changes and restoration on quit use XPC without repeated authentication. The app stores neither your password nor a `sudo` session.
- **Remove…**: Turn off closed-lid mode and restore the previous power settings before removing the helper. Removal requires administrator authentication.

You can use closed-lid mode without registering the helper by authenticating for each change. Configure the separate Do Not Disturb shortcuts in the **Do Not Disturb** tab.

Helper approval survives restarting the same app build. Development ad-hoc signatures are tied to the app’s code hash, so a new build displays **App updated · Renew approval** and requires **Approve Update…** once. The existing helper remains installed. Distribution builds signed with the same Developer ID can identify the app and helper through stable signing requirements. To specify a signing identity, use `NONSLEEP_SIGNING_IDENTITY='Developer ID Application: …' ./scripts/build.sh`.

### Connect Do Not Disturb shortcuts

1. In Apple Shortcuts, create two shortcuts with the **Set Focus** action.
2. Configure the first to turn **Do Not Disturb** **On**, **Until Turned Off**.
3. Configure the second to turn **Do Not Disturb** **Off**. Use explicit On and Off actions rather than a toggle.
4. In NonSleep’s **Settings → Do Not Disturb**, refresh the list and select each shortcut.
5. To silence notifications, open **System Settings → Focus → Do Not Disturb**, remove allowed people and apps, and turn off exceptions such as repeated calls and time-sensitive notifications. NonSleep cannot override exceptions that macOS permits, including certain critical alerts.

Run both shortcuts directly in Shortcuts once, approve any prompts, and confirm **Do Not Disturb** changes in Control Center. Then use **Test On** and **Test Off** in NonSleep. Execution and list errors appear in the setup screen; **Edit Shortcut** opens the selected shortcut for troubleshooting.

NonSleep stores stable shortcut identifiers, so renaming a connected shortcut preserves its connection. Older name-based connections are migrated when the list is refreshed; if a name is duplicated or a shortcut has been deleted, select the intended shortcut again. Identifiers are passed as process arguments, never inserted into a shell. NonSleep only checks the shortcut’s exit status. It cannot inspect the shortcut’s actions or verify the actual Focus state, so the switch shows the **last execution request**. The state is unknown after relaunching the app or changing Focus directly in macOS. To turn it off while the status is unknown, use the Do Not Disturb row’s context menu or **Test Off** in Settings. Focus remains enabled after quitting NonSleep.

### Closed-lid mode and restoration

`disablesleep` is a system-wide setting that blocks both closed-lid sleep and normal system sleep. While closed-lid mode is on, system sleep remains blocked even if Keep Awake is off. Display sleep prevention follows the Keep Awake switch. Without a registered helper, enabling, disabling, and restoring closed-lid mode on quit may require administrator authentication.

The app saves the original setting before making a change. On normal quit, it restores the power settings it changed. If restoration fails or authentication is canceled, the app stops quitting and displays an error. It does not disable settings that another app had already enabled before launch. Settings may remain changed after a forced quit or power loss; use **Restore** on the next launch. To disable the setting manually without the app, run:

```sh
sudo pmset -a disablesleep 0
```

`disablesleep` exists in Apple’s power management source but is not documented in the public `pmset` manual. Closed-lid behavior needs verification on each Mac and macOS version. Sleep prevention does not override low-power or thermal protection, or forced shutdowns. Keep your Mac in a ventilated area when using it with the lid closed.

## Power helper architecture

The code-signed `NonSleepHelper` executable runs as an on-demand launchd Mach service. Local builds install it through administrator authentication without requiring an Apple-issued signing certificate. Only these three files are installed at fixed paths, owned by root:

```text
/Library/PrivilegedHelperTools/dev.nonsleep.helper
/Library/PrivilegedHelperTools/dev.nonsleep.helper.client-requirement
/Library/LaunchDaemons/dev.nonsleep.helper.plist
```

The app and helper both verify the other’s code signature through `NSXPCConnection.setCodeSigningRequirement`. The installer copies the helper into a root-only staging directory, verifies its expected code signature, and installs it. The service configuration and client signing requirement are also generated in that directory. The helper accepts only connection checks and a Boolean `SleepDisabled` value; it accepts no commands, paths, or passwords. It invokes `/usr/bin/pmset` with fixed arguments. Restoration records remain available on the next launch even after a forced quit.

Tests cover creation and release of real IOKit assertions, login registration and removal failures, external revocation, anonymous XPC messaging, and matching or mismatched code-signing requirements. Privileged XPC connections, administrator installation and removal, and launch at login after signing in are integration checks that require user authorization. Tests do not install the administrator helper or change system login settings.

## Distribution

The build script currently uses development ad-hoc signing. Developer ID signing and Apple notarization for external distribution are not included by default. The app runs administrator commands and does not use App Sandbox. An App Store release would require a separate design.

### In-app updates

Open **Settings → Updates**, or right-click the menu bar icon and choose **Check for Updates…**.

- The app checks the GitHub API endpoint `mars2cbh/NonSleep/releases/latest` for the latest stable release. Drafts and prereleases are excluded.
- Automatic checks are enabled by default. Once six hours have passed since the last attempt, the app checks at launch or while running. You can disable automatic checks in Settings. You choose when to download and install.
- When an update is available, choose **Download and Install…**. Sparkle handles downloading, signature verification, installation, and relaunching. The app selects the ZIP for your Mac’s architecture.
- The app displays a status when no release exists, the network is unavailable, GitHub rate-limits requests, or release files are missing.
- Both the update feed and ZIP require valid Ed25519 signatures. ZIPs are verified before extraction. Update installation also follows the existing power restoration procedure when quitting. If restoration is canceled or fails, the app does not quit.

Ad-hoc builds may require **Approve Update…** for the closed-lid power helper once after an update. Signing distribution builds with the same Developer ID can reduce this limitation.

### CalVer versions

Tags and displayed versions use **`YYYY.MM.DD[.N]`**: for example, `2026.11.25`, an additional release on the same day as `2026.11.25.1`, and the next day as `2026.11.26`. Dates are validated, and months and days use two digits. Prereleases can use a suffix such as `2026.11.25-beta.1`.

`CFBundleShortVersionString` contains the three-part date. `NonSleepReleaseVersion` contains the full version, including the additional release number. Sparkle orders installations using `CFBundleVersion`, which is the Actions run number, so use the release workflow for distribution. Version comparisons also support migration from earlier SemVer builds.

### Create GitHub Releases automatically

`.github/workflows/release.yml` runs tests and builds the app on both Apple Silicon and Intel when you push a version tag. It creates and verifies the DMGs, signs the ZIPs and update feeds, then attaches these files to the release:

- `NonSleep-<version>-macos-arm64.dmg`: Apple Silicon installer
- `NonSleep-<version>-macos-x86_64.dmg`: Intel installer
- `NonSleep-<version>-macos-arm64.zip`, `NonSleep-<version>-macos-x86_64.zip`: In-app update and manual extraction archives
- `appcast-arm64.xml`, `appcast-x86_64.xml`: In-app update feeds
- `SHA256SUMS.txt`: SHA-256 checksums for the DMGs, ZIPs, and feeds

Replace the example tag below with an unused CalVer version:

```sh
git tag -a v2026.11.25 -m "NonSleep 2026.11.25"
git push origin v2026.11.25
```

You can also run **Actions → Release → Run workflow** on GitHub:

- **Publish a release**: Leave `tag` empty and enable `publish`. The workflow builds the selected branch and creates a CalVer tag using today’s date in the Asia/Seoul time zone. If that date already has a tag, it uses the next additional release number, such as `.1` or `.2`.
- **Publish an existing tag**: Enter an existing CalVer tag and enable `publish`. The workflow builds the commit that tag points to. Tags entered explicitly must already exist.
- **Build only**: Leave `tag` empty and disable `publish`. The workflow uses the app’s recorded version, builds and verifies signed files, and stores Actions artifacts without publishing a release.

Automatic tags are created only after builds and signature verification succeed. If the same tag name has appeared on a different commit, the workflow stops without overwriting it.

Releases are published after all files have been verified and uploaded. Published releases are never overwritten. A draft from a failed run can be resumed when rerunning the job. Use a new version tag for subsequent changes. Tags with suffixes such as `-beta.1` are published as prereleases.

### Update signing keys

This repository has a `SPARKLE_PRIVATE_KEY` Actions secret configured. The public key is recorded in `Resources/Info.plist` as `SUPublicEDKey`. The workflow verifies that the private key matches the app’s public key and passes the private key to the signing tool through standard input only. Private keys are excluded from ZIPs, artifacts, and logs. The signing tool download is also verified against a pinned SHA-256 checksum.

The local key backup is outside the repository at `~/Library/Application Support/NonSleep/ReleaseSigning/ed25519.key`, with file permissions set to `600`. Back it up securely. Losing or replacing the key without a migration plan can prevent installed apps from verifying future updates.

Forks need their own signing key, matching public key, and Actions secret. Also change the GitHub repository URLs in the app and release scripts to point to your repository.

```sh
swift scripts/update-key.swift create /secure/location/ed25519.key
# Set SUPublicEDKey in Info.plist to the public key printed above.
gh secret set SPARKLE_PRIVATE_KEY --repo OWNER/REPO < /secure/location/ed25519.key
```

The current artifacts are **ad-hoc signed and not notarized**. Sparkle update signatures do not replace Developer ID signing or Apple notarization. Licenses for Sparkle and its included libraries are in `Resources/Sparkle-LICENSE.txt` and are distributed with the app.

To build locally with explicit version information in a separate directory:

```sh
NONSLEEP_VERSION=2026.11.25 NONSLEEP_BUILD_NUMBER=10 \
NONSLEEP_APP_DIR="$PWD/build/release/NonSleep.app" ./scripts/build.sh
```

### Build a DMG locally

After building the app, use Python 3.11 or later to install the packaging tools in a virtual environment. CI uses Python 3.12. Tool versions and wheel hashes are pinned in `scripts/dmg-requirements.txt`.

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/python -m pip install --only-binary=:all: --require-hashes -r scripts/dmg-requirements.txt
.build/dmg-tools/bin/python scripts/create_dmg.py \
  --app build/NonSleep.app --arch arm64 \
  --output dist/NonSleep-2026.11.25-macos-arm64.dmg
```

For an Intel app bundle, use `--arch x86_64` and the matching output filename. The script verifies the app’s architecture and code signature, creates the disk image, then mounts it read-only to check its contents, Applications shortcut, and app signature.

## References

- [Apple: Scope of idle sleep prevention assertions](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Apple: Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)
- [Apple: Login items and service management](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple: XPC connection code-signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
- [Apple source: pmset disablesleep handling](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Sparkle: Update integration and signing](https://sparkle-project.org/documentation/)
- [GitHub: Latest release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
