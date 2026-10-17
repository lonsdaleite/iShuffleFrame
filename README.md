# iShuffleFrame

A photo frame app for old iPads: a full-screen slideshow of photos from the device's photo library,
including iCloud shared albums. It starts the slideshow on launch, so an external script can turn the frame
on with a single `uiopen`.

## Builds

| | Regular build | Legacy build |
|---|---|---|
| How | Xcode project generated from `project.yml` | `make` |
| Toolchain | current Xcode and SDK | clang from current Xcode + iOS 9.3 SDK |
| Architectures | arm64 | armv7 + arm64 |
| Minimum iOS | 15.0 (the lowest current Xcode accepts) | 9.3 |
| Signing / delivery | developer certificate: direct install, TestFlight, App Store | fakesigned `.deb` for a jailbroken device: `/Applications`, or `/var/jb/Applications` for rootless |

One Objective-C codebase for both. Swift is not used: it does not target armv7 / iOS 9 with current toolchains.
The legacy build may later get extra features that the App Store would not allow.

### Regular build and tests

```sh
brew install xcodegen
make test        # xcodegen generate + unit and UI tests on the iPad mini simulator
```

UI tests run the app with generated demo photos (`-ISFDemo YES`, debug builds only).

### Legacy build

```sh
brew install ldid dpkg
make sdk         # downloads the iOS 9.3 SDK into ~/theos/sdks (see scripts/fetch-sdk.sh)
make deb         # build/legacy/com.lonsdaleite.ishuffleframe_<version>-<build>_iphoneos-arm.deb
make deb ROOTLESS=1  # build/rootless/…_iphoneos-arm64.deb for rootless jailbreaks (Dopamine, palera1n)
```

- armv7 is compiled as ARM, not Thumb: the current linker drops the Thumb bit from the entry point and method
  addresses, and such a binary dies with SIGILL on launch.
- The binary is signed with `packaging/entitlements.plist` (no sandbox, no data container, like Sileo or Filza).
  Without it, on iOS 15 under Dopamine the app gets a container it cannot write to, and settings and the cycle
  are not saved. The app keeps its files in `/var/mobile/Library` (Dopamine moves the preferences of rootless
  apps to `/var/jb/var/mobile/Library/Preferences`).
- The icon is `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, drawn by `scripts/make-icon.py`
  (Pillow); the legacy build resizes it into plain PNG files, as current Xcode does not compile asset catalogs
  for iOS 9.

Linking against the iOS 9.3 SDK stubs guarantees that every imported symbol exists on iOS 9.3. Current clang
always emits some newer runtime calls; `-fno-objc-convert-messages-to-runtime-calls` keeps `objc_alloc` and
friends out, and the stubs catch the rest at link time. The binary cannot run on the Mac, so the legacy build is
only checked on a device.

Install on the device: `dpkg -i <deb>`; the post-install script registers the app with SpringBoard.

## Features

Photo source:
- Any set of albums, including iCloud shared albums, or all photos. Chosen in the settings screen.
- New photos in the selected albums are picked up while the slideshow runs (PhotoKit change observer).
- Videos are skipped; Live Photos are shown as still images.

Slideshow:
- Order: shuffled (no repeats within a cycle, reshuffled after each cycle) or sequential.
- The cycle continues after a relaunch (the app is usually killed and relaunched by scripts). Its state is saved
  every 5 minutes and when the app stops, goes to the background or the library changes, so a killed app replays
  at most a few minutes of photos.
- Interval is configurable.
- Transition: none (default) or fade.
- Black background; the photo is fitted to the screen with black bars. Nothing is drawn over the photo.
- No status bar; the screen does not auto-lock while the slideshow runs.
- The next photo is decoded ahead of time at screen size (the iPad 3 has 1 GB RAM). The app requests the file
  data from PhotoKit and decodes it with ImageIO: shared-album JPEGs carry both JFIF and Exif headers, and on
  iOS 15 on A8X (iPad Air 2) both PhotoKit and ImageIO decode them into black images unless the JFIF segment is
  removed first.
- A photo that fails to load (or does not load within 60 s, e.g. a stalled iCloud download) is skipped. After five
  failures in a row the last photo stays on screen and the failing one is retried every interval, so a short
  iCloud outage does not use up the cycle. A photo that still fails after three retries is skipped (during a
  long outage that is one photo every four intervals).
- If a selected album is briefly unavailable (e.g. while iCloud syncs), photos already shown in the current cycle
  are not shown again when it comes back; an empty photo list is not applied while photos are on screen.

Controls:
- Swipe left/right: next/previous photo within the current cycle; the cycle order is kept. The photo slides in
  from the side whatever the transition setting.
- Tap: pause and show a menu with Resume and Settings; the screen stays on. A tap next to the menu resumes too,
  and a swipe does not count as a tap. The menu closes itself and the slideshow resumes after 2 minutes without
  an answer. Start Slideshow in the settings continues the cycle with the new settings.
- Autostart (on/off in settings): when on, the app starts the slideshow on launch with the saved settings.
  When no source is selected yet, the app opens the settings instead.
- URL scheme for scripts (e.g. `uiopen` on a jailbroken device): `ishuffleframe://start` starts the slideshow (closing
  the settings or the pause menu) and does nothing when it is already running; `ishuffleframe://settings` opens
  the settings.
- Selected albums that are not in the library at the moment (deleted, left, still syncing) stay selected and are
  listed as unavailable, where they can be unticked. Empty smart albums are hidden from the list, so a selected
  smart album that became empty is listed as unavailable too.

Out of scope for v1: Home Assistant integration, overlays (clock, dates), Ken Burns, side-by-side portrait
photos.

All Photos is the device photo library; iCloud shared albums are not part of it and are picked as albums.

## Devices it is built for

- iPad 3 (iPad3,1), iOS 9.3.5, jailbroken: legacy build.
- iPad mini 2 (iPad4,4), iOS 12.5.8, jailbroken: legacy build (the regular build needs iOS 15).
- iPad Air 2, iOS 15.8, Dopamine (rootless): legacy build with `ROOTLESS=1`.

## Known limits

- The regular build still uses the app-delegate window lifecycle. Current iOS warns that `UIScene` will become
  required; it has to be adopted for the regular build only (iOS 9 has no scenes).
- On the iOS 26+ simulator `XCUIApplication.openURL` relaunches the app, so a URL sent to a running slideshow is
  only checked on a device.
