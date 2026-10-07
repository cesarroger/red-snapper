# Developing RED SNAPPER

Everything technical lives here. The [README](README.md) is the friendly version for people who just want snapping.

**Stack:** Swift 5 mode, AppKit + SwiftUI, macOS 14+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the project file, [Sparkle](https://sparkle-project.org) for updates. No other dependencies.

## Project layout

```
project.yml                 XcodeGen spec (source of truth for RedSnapper.xcodeproj)
SnapCore/                   Pure logic, no AppKit/AX. Fully unit-tested (71 tests).
  SnapZone.swift            Zones as spans of a columns×rows grid
  LayoutEngine.swift        zone + visibleFrame + gap → CGRect; min-size re-anchoring
  CoordinateConverter.swift AppKit (bottom-left) ⇄ Accessibility (top-left) flip
  ScreenMath.swift          which display a window is on, next/prev/left/right display, relocation
  DragZoneDetector.swift    cursor position → drag zone
  SnapCycle.swift           press-again cycling and display hops
  DragRestore.swift         restore-on-drag geometry
  GridPlanner.swift         4-up: pick windows by recency, zones by window count
  SavedLayout.swift         layout model + matching saved windows to open ones
  PreferencesStore.swift    every preference in UserDefaults
  HotKeyModel.swift         KeyCombo, HotKeyAction, default bindings, key names
SnapCoreTests/              XCTest for all of the above
RedSnapper/
  App/                      Entry point, AppDelegate, menu bar, observable settings
  Accessibility/            AX wrapper, WindowManager, drag-to-snap, title-bar tap, MRU tracker
  HotKeys/                  Carbon RegisterEventHotKey manager
  UI/                       Onboarding, Settings, shortcut recorder, snap picker, preview overlay, HUD
  Resources/                Asset catalog with the app icon
```

**Threading.** Accessibility calls block for up to the messaging timeout (0.3 s) when the target app is hung. So every window operation snapshots the screens and settings into a `SnapContext` on the main thread, then does its AX work on a background queue. Drag detection uses its own queue. The only AX call on the main thread is the title-bar right-click check, which is capped at 50 ms and only runs for right-clicks in a title-bar band. Measured with an app frozen: the worst main-thread delay was 35 ms, the same as idle.

## Build & run in Xcode

1. Open `RedSnapper.xcodeproj` (regenerate it with `xcodegen generate` after adding or removing files).
2. Pick the **RED SNAPPER** scheme with destination **My Mac**.
3. **⌘R** to run, **⌘U** to run the SnapCore unit tests.
4. On first launch, grant Accessibility: click **Open System Settings**, then turn on **RED SNAPPER** under *Privacy & Security → Accessibility*.
5. Look for the 🐟 in the menu bar. There's no Dock icon. Launching the app again while it's running opens Settings.

Signing uses the maintainer's *Apple Development* certificate (team `2D79JL74UU`, set in `project.yml`). A stable signature means the Accessibility grant survives rebuilds. **Contributors:** change `DEVELOPMENT_TEAM` to your own team, or set `CODE_SIGN_IDENTITY: "-"` to sign locally. With ad-hoc signing you'll need to re-grant Accessibility after each rebuild.

## Releasing (direct download)

RED SNAPPER can't ship on the Mac App Store. Every App Store app must be sandboxed, and sandboxed apps can't use the Accessibility API that moves other apps' windows. Apple's developer support recommends Developer ID distribution for window managers ([forum answer](https://developer.apple.com/forums/thread/805556)).

One command builds a signed, notarized release:

```bash
scripts/release.sh
```

It runs the tests, archives a universal build (Apple silicon + Intel), signs it with your Developer ID, sends it to Apple for notarization, staples the ticket, checks it with Gatekeeper, and writes:

- `dist/RED-SNAPPER-<version>.zip`: **the recommended download.** Fully notarized and opens without warnings.
- `dist/RED-SNAPPER-<version>.dmg`: drag-to-Applications disk image. The app inside is notarized; the image wrapper itself is unsigned.

Signing and notarization use the Apple Developer account Xcode is signed in to (*Xcode → Settings → Accounts*), so no passwords are needed. Notarization is free with the Developer Program.

To also notarize the .dmg wrapper, create a `notarytool` profile once (an App Store Connect API key is the most reliable):

```bash
xcrun notarytool store-credentials RedSnapperNotary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
```

### Auto-updates (Sparkle)

The app checks `appcast.xml` on the `main` branch for new versions. Each update is signed with an EdDSA key whose public half is in `RedSnapper/Info.plist` (`SUPublicEDKey`). The private half lives only in the release machine's keychain (Sparkle account `red-snapper`). **Back it up**: if it's lost, existing installs can never be updated again.

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account red-snapper -x red-snapper-sparkle-key.txt
```

Keep that file in a password manager, not in the repo.

### Shipping a new version

1. Bump `MARKETING_VERSION` **and** `CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle compares the build number, so it must go up every release.
2. Run `scripts/release.sh`. It signs the update and adds it to `appcast.xml`.
3. Publish the GitHub release **first**, then push the appcast. Otherwise apps go looking for a file that isn't there yet:

```bash
gh release create v1.1 dist/RED-SNAPPER-1.1.zip dist/RED-SNAPPER-1.1.dmg --title "RED SNAPPER 1.1" --notes "What's new…"
```

```bash
git add appcast.xml project.yml && git commit -m "Release 1.1" && git push
```

To install it yourself, unzip and drag **RED SNAPPER.app** to `/Applications`. macOS asks for Accessibility permission once for that copy. Turn *Launch at login* off and on again from it so the login item points there.

## Behaviour notes

- **Menu bar & Dock**: layouts use `NSScreen.visibleFrame`, so the menu bar and Dock are never covered. The gap is applied at the screen edges and between windows.
- **Windows with a minimum or fixed size** keep the size they insist on, are pinned to the zone's outer edge(s), and stay on screen.
- **Restore** remembers the frame from before the *first* snap, so cycling through several sizes and then restoring goes back to where you started. Moving or resizing a window by hand starts the memory over.
- **Snap picker** picks are exact: choosing *Left Half* twice doesn't cycle. Right-clicks on toolbar buttons, tabs or window content are left alone.
- **Saved layouts** match windows by app and document title first, then by stacking order. Apps that aren't running are skipped and listed in the confirmation notice. Saving under an existing name replaces that layout and keeps its shortcut.
- **macOS's own edge tiling** (on by default since macOS 15) also reacts to edge drags. RED SNAPPER re-applies its zone if macOS moves the window afterwards. For the smoothest drags, turn it off in *System Settings → Desktop & Dock*.
- **Stage Manager**: windows parked in other stages are skipped by the 4-up grid and layouts.
- Settings live in `UserDefaults` (`com.csr.RedSnapper`). Reset everything with:

```bash
defaults delete com.csr.RedSnapper
```
