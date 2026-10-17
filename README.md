# iShuffleFrame

A photo frame app for iPads: a full-screen slideshow of photos from the device's photo library, including iCloud
shared albums. It starts the slideshow on launch and takes `ishuffleframe://` URLs, so an external script can
turn the frame on with a single `uiopen`. It runs on old jailbroken iPads (iOS 9.3 and up) and on current ones.

## Builds

| | Regular build | Legacy build |
|---|---|---|
| How | Xcode project generated from `project.yml`; `make ipa` | `make deb` |
| Toolchain | current Xcode and SDK | clang from current Xcode + iOS 9.3 SDK |
| Architectures | arm64 | armv7 + arm64 (arm64 only with `ROOTLESS=1`) |
| Minimum iOS | 15.0 (the lowest current Xcode accepts) | 9.3 |
| Delivery | unsigned `.ipa` for TrollStore or sideloading; `.ipa` signed for development | fakesigned `.deb` for a jailbroken device: `/Applications`, or `/var/jb/Applications` for rootless |

One Objective-C codebase for both. Swift is not used: it does not target armv7 / iOS 9 with current toolchains.
The legacy build may later get extra features that the App Store would not allow.

Both builds have the bundle ID `com.lonsdaleite.ishuffleframe`, so a device has either the `.deb` or the `.ipa`.
They keep their settings and cycle in different places (see below), which do not move over when one is replaced
by the other.

### Regular build and tests

```sh
brew install xcodegen
make test                # xcodegen generate + unit and UI tests on the iPad mini simulator
make ipa                 # build/ipa/iShuffleFrame_<version>-<build>.ipa: Release build, unsigned
make ipa TEAM=<team id>  # build/ipa/…_development.ipa, signed for development
```

- UI tests run the app with generated demo photos (`-ISFDemo YES`, debug builds only).
- The unsigned `.ipa` is for installers that sign it themselves: TrollStore, Sideloadly, AltStore.
- With `TEAM` the build is signed with automatic signing and the profiles already on this Mac (e.g. the team's
  wildcard profile), so it runs only on devices registered in that profile. Install it on a device paired with
  this Mac (Developer Mode on) with
  `xcrun devicectl device install app --device <udid> build/ipa/iShuffleFrame.xcarchive/Products/Applications/iShuffleFrame.app`.
- There is no TestFlight or App Store build yet: it needs an App ID and a distribution certificate in the
  developer account.
- The regular build uses the scene lifecycle (`ISFSceneDelegate`): iOS 27 terminates apps built with its SDK
  that do not.
- Installed this way the app is sandboxed and keeps its settings and cycle in its data container.

### Legacy build

```sh
brew install ldid dpkg
make sdk             # downloads the iOS 9.3 SDK into ~/theos/sdks (see scripts/fetch-sdk.sh)
make deb             # build/legacy/com.lonsdaleite.ishuffleframe_<version>-<build>_iphoneos-arm.deb
make deb ROOTLESS=1  # build/rootless/…_iphoneos-arm64.deb for rootless jailbreaks (Dopamine, palera1n)
```

Install on the device: `dpkg -i <deb>`; the post-install script registers the app with SpringBoard.

- Linking against the iOS 9.3 SDK stubs guarantees that every imported symbol exists on iOS 9.3. Current clang
  always emits some newer runtime calls; `-fno-objc-convert-messages-to-runtime-calls` keeps `objc_alloc` and
  friends out, and the stubs catch the rest at link time. The binary cannot run on the Mac, so the legacy build is
  only checked on a device.
- armv7 is compiled as ARM, not Thumb: the current linker drops the Thumb bit from the entry point and method
  addresses, and such a binary dies with SIGILL on launch.
- No scenes: `ISFSceneDelegate` needs the iOS 13 SDK and is compiled out, and the scene manifest is dropped from
  Info.plist, so the app delegate creates the window.
- The binary is signed with `packaging/entitlements.plist` (no sandbox, no data container, like Sileo or Filza).
  Without it, on iOS 15 under Dopamine the app gets a container it cannot write to, and settings and the cycle
  are not saved. The app keeps its files in `/var/mobile/Library` (Dopamine moves the preferences of rootless
  apps to `/var/jb/var/mobile/Library/Preferences`).

### Icon

`Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, drawn by `scripts/make-icon.py` (Pillow). The legacy
build resizes it into plain PNG files, as current Xcode does not compile asset catalogs for iOS 9.

## Features

Photo source:
- Any set of albums, including iCloud shared albums, or all photos. Chosen in the settings screen.
- New photos in the selected albums are picked up while the slideshow runs (PhotoKit change observer).
- Videos are skipped; Live Photos are shown as still images.

Slideshow:
- Order: shuffled (no repeats within a cycle, reshuffled after each cycle) or sequential.
- The cycle continues after a relaunch (the app is usually killed and relaunched by scripts). Its state is saved
  every 5 minutes and when the app stops, resigns active or the library changes, so a killed app replays at most
  a few minutes of photos.
- The slideshow stops only in the background. While the app is merely inactive (Control Center, an alert) it
  keeps going.
- Interval is configurable.
- Transition: none (default) or fade.
- Black background; the photo is fitted to the screen with black bars. Nothing is drawn over the photo.
- No status bar; the screen does not auto-lock while the slideshow runs or the pause menu is open.
- Photos are decoded at screen size ahead of time: the next three and the previous one. Up to seven decoded
  photos stay in memory (about 12 MB each on a 2048 × 1536 screen), so swiping back and forth is instant; one
  request per photo however many places wait for it. This also hides slow first downloads of shared-album photos
  from iCloud, which take up to tens of seconds on the iPad 3.
- The app requests the file data from PhotoKit and decodes it with ImageIO: shared-album JPEGs carry both JFIF
  and Exif headers, and on iOS 15 on A8X (iPad Air 2) both PhotoKit and ImageIO decode them into black images
  unless the JFIF segment is removed first.
- A photo that fails to load (or does not load within 60 s, e.g. a stalled iCloud download) is skipped. After five
  failures in a row the last photo stays on screen and the failing one is retried every interval, so a short
  iCloud outage does not use up the cycle. A photo that still fails after three retries is skipped (during a
  long outage that is one photo every four intervals).
- If a selected album is briefly unavailable (e.g. while iCloud syncs), photos already shown in the current cycle
  are not shown again when it comes back; an empty photo list is not applied while photos are on screen.

Controls:
- Swipe left/right: next/previous photo within the current cycle; the cycle order is kept. The photo slides in
  from the side whatever the transition setting.
- Tap: pause and show a menu with Resume and Settings. A tap next to the menu resumes too, and a swipe does not
  count as a tap. The menu closes itself and the slideshow resumes after 2 minutes without an answer. Start
  Slideshow in the settings continues the cycle with the new settings.
- Autostart (on/off in settings): when on, the app starts the slideshow on launch with the saved settings.
  When no source is selected yet, the app opens the settings instead.
- URL scheme: `ishuffleframe://start` starts the slideshow (closing the settings or the pause menu) and does
  nothing when it is already running; `ishuffleframe://settings` opens the settings. On a jailbroken device
  scripts call it with `uiopen`; elsewhere it can be opened from Shortcuts.
- Selected albums that are not in the library at the moment (deleted, left, still syncing) stay selected and are
  listed as unavailable, where they can be unticked. Empty smart albums are hidden from the list, so a selected
  smart album that became empty is listed as unavailable too.

Out of scope for v1: Home Assistant integration, overlays (clock, dates), Ken Burns, side-by-side portrait
photos.

All Photos is the device photo library; iCloud shared albums are not part of it and are picked as albums.

## Devices

| Device | iOS | Build | Settings and cycle |
|---|---|---|---|
| iPad 3 (iPad3,1) | 9.3.5, jailbroken | `make deb` | `/var/mobile/Library` |
| iPad mini 2 (iPad4,4) | 12.5.8, jailbroken | `make deb` (the regular build needs iOS 15) | `/var/mobile/Library` |
| iPad Air 2 | 15.8, Dopamine (rootless) | `make ipa`, installed with TrollStore; `make deb ROOTLESS=1` also works | app data container |
| iPad mini 6 (iPad14,1) | 27, not jailbroken | `make ipa TEAM=…`, installed with `devicectl` | app data container |

## Known limits

- On a device without a jailbreak nothing outside the app can start, lock or unlock it remotely; the frame has
  to stay on (Auto-Lock off, Guided Access) or be driven by Shortcuts automations.
- A development-signed build stops launching when its provisioning profile expires; the device needs a fresh
  install then.
- On the iOS 26+ simulator `XCUIApplication.openURL` relaunches the app, so a URL sent to a running slideshow is
  only checked on a device.
