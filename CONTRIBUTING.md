# Contributing to Rin

Thanks for your interest in Rin. This guide covers how to report a problem, how the project is organized, and the conventions a change should follow.

## Reporting a problem

Open an [issue](https://github.com/Cocojcc/Rin/issues) and include:

- Your Rin version, macOS version and Mac model
- What you did, what you expected and what happened
- A screenshot, if the problem is visible

## Setting up

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Rin.xcodeproj` is generated from `project.yml`, so run this again after adding or removing source files:

```bash
xcodegen generate
```

Build and run a debug version:

```bash
xcodebuild -project Rin.xcodeproj -scheme Rin -configuration Debug -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/Rin.app
```

You can also open `Rin.xcodeproj` in Xcode and run it from there.

## Project layout

| Directory | Contents |
|---|---|
| `Rin/App` | App entry point and lifecycle |
| `Rin/Core` | Sampling (`Monitor`), history, settings, alerts, process actions, theme, localized text |
| `Rin/Readers` | Data collection: CPU, memory, network, disk, battery, Bluetooth and Logitech devices, SMC, IOReport, processes |
| `Rin/MenuBar` | Status items, widgets and the dropdown window |
| `Rin/Popovers` | The module dropdowns and the combined dropdown |
| `Rin/Window` | The main window: overview, module pages, processes, alerts, sleep, settings, about |
| `Rin/Resources` | Assets and localized strings |
| `Rin/Support` | `Info.plist`, entitlements and the bridging header |
| `Rin/Debug` | Snapshot tools, compiled into debug builds only |

## Conventions

### Text

All user-visible text, including accessibility labels and help tags, goes through `Rin/Core/L10n.swift`, with translations in `Rin/Resources/*.lproj/Localizable.strings`. After changing text, check that both languages are complete:

```bash
python3 scripts/check-l10n.py
```

### Power use

Rin runs all day, so a new reading has to justify its cost:

- Read only while something shows the value or an alert rule needs it.
- Close devices after reading, and cache values that do not change.
- Do not wake peripherals.
- Avoid SwiftUI animations on values that change with most readings. Use Core Animation layers instead, as `OverviewLineView` does.

To measure a change, launch the app with `open`, keep its window in front, and compare `ps -o cputime` over a fixed time. A binary started directly from a terminal reports lower numbers, because its window is not frontmost.

### Commits

Write commit messages in the imperative, with a subject that says what changes for the user or the code.

## Checking the interface

Debug builds can export the interface as PNG files, in light and dark:

```bash
build/DerivedData/Build/Products/Debug/Rin.app/Contents/MacOS/Rin --snapshot /tmp/rin-snap
```

This renders menu bar widgets, dropdowns and window pages off screen. The argument after the directory limits it to a group such as `panel` or `page`, or to one page such as `page-cpu`:

```bash
build/DerivedData/Build/Products/Debug/Rin.app/Contents/MacOS/Rin --snapshot /tmp/rin-snap page-cpu
```

| Environment variable | Effect |
|---|---|
| `RIN_SNAPSHOT_WAIT=<seconds>` | Reads for longer before drawing, so curves have data. The default is 7. |
| `RIN_SNAPSHOT_WIDTH=<points>` | Sets the window width, for checking narrow layouts. |

Add `-AppleLanguages '(en)'` after that argument to check another language. To render everything in another language, pass an empty filter first, as in `--snapshot /tmp/rin-snap "" -AppleLanguages '(en)'`.

Snapshots read every module and draw some views differently, so check values such as CPU frequency and temperature in a real window too. To export the real status items, dropdowns and pages from a running app:

```bash
build/DerivedData/Build/Products/Debug/Rin.app/Contents/MacOS/Rin --dump-live /tmp/rin-live
```

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

## Releasing

Maintainers publish releases as follows.

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then run `xcodegen generate`.
2. Add the version to `CHANGELOG.md`.
3. Build, sign and notarize the disk image, which ends up at `build/release/Rin-<version>.dmg`:

   ```bash
   scripts/release.sh
   ```

4. Commit, tag the commit as `v<version>`, and push both.
5. Publish a GitHub release for the tag, attach the disk image, and use this format for its notes:

   ```markdown
   ## What's Changed

   ### Added
   - ...

   ### Changed
   - ...

   ### Fixed
   - ...

   ## Installation

   Download `Rin-<version>.dmg` below, open it and drag Rin to Applications. Rin requires macOS 14 or later on Apple silicon. It is signed with a Developer ID and notarized by Apple.

   ## Checksum

   SHA-256: `<checksum>`

   See [CHANGELOG.md](https://github.com/Cocojcc/Rin/blob/master/CHANGELOG.md) for the full history.
   ```

   List only the sections a release needs, and use the same entries as `CHANGELOG.md`.

`scripts/release.sh` needs a Developer ID Application certificate in the keychain, and notary credentials saved with:

```bash
xcrun notarytool store-credentials rin-notary --apple-id <apple-id> --team-id <team-id>
```
