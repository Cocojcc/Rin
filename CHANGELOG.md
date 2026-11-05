# Changelog

All notable changes to Rin are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Rin updates itself: Check for Updates in Settings downloads the new version, verifies its signature, installs it and restarts. An automatic check only puts the new version on the button. Rin 0.6.3 and earlier need one last update from the disk image.

## [0.6.3] - 2026-11-05

### Added

- The MIT License.

### Changed

- Processes: five tabs replace the table of columns: CPU, Memory, Network, Disk and Energy, each with the columns that answer it. CPU adds threads and PID; Memory adds compressed memory; Network and Disk show the last minute's average next to what each app has moved since launch; Energy shows power and energy used.
- Processes: a column with nothing to show for the current tab and filter is hidden.
- Processes: with the inspector open, the list keeps its first two columns, or the first and the one being sorted by.
- Processes: the process type filter moved to a menu above the list, and the rows are striped.
- Sidebar: the selected page uses the same pale tile on every page, and module icons keep their color.
- Sidebar: wider, so the window buttons sit fully on it, with the middle one over the icons.

### Fixed

- Combined dropdown: rows for modules not being read appeared a moment after it opened, and the dropdown grew. They now show their last readings at once.
- Narrow windows: rows with a reading, such as Frequency on the CPU page, hide their breakdown instead of truncating their label.
- Memory page: in English, the Compressed label no longer runs into the one beside it.
- Memory of other users' processes, such as WindowServer, now matches Activity Monitor on the Processes page, the Memory page and the Memory dropdown. It updates every 30 seconds while one of them is open.

## [0.6.2] - 2026-11-04

### Changed

- Overview: the Network row shows download and upload side by side, with a line for each. Its detail now states the connection, such as "Wi-Fi Connected".
- Combined dropdown: the Network row has a bar and a reading for each direction. When Network leads the dropdown, both speeds are shown large.
- Each direction's line is measured against its own peak over the last hour.

## [0.6.1] - 2026-11-04

### Changed

- Combined dropdown: every row below the lead module now has a name, one thin bar and one reading, instead of a mix of curves and bars.
- Combined dropdown: bars turn red with their reading when CPU or temperature reaches 90, or when a battery is low.
- Combined dropdown: Accessories shows only its reading when it leads, because it keeps no curve.
- Upload and fan speed moved from the combined dropdown's rows to the details beside them.

## [0.6.0] - 2026-11-04

### Changed

- Overview is now a list with one row per module: name, detail, reading and a thin proportional line. Selecting a row opens the module's page.
- Module pages and dropdowns use taller curves and smaller, neutral lead readings. A low battery still turns red, and a bolt marks charging.
- Bars and curves are thinner, curve fills are lighter, and alert lines are finer.
- Disk: a thin capacity bar for used, purgeable and free space replaces the platter.
- Rin uses less CPU while the Overview is open.

### Removed

- The module instruments.
- The Overview's time range control. History is on the module pages.

### Fixed

- English: figures on the CPU page were pushed out of the window.
- English: labels were truncated in the CPU dropdown and on the Sensors page.

## [0.5.0] - 2026-11-03

### Added

- A small instrument for each module on the Overview, module pages and dropdowns, driven by live readings.

### Changed

- The sidebar runs the full height of the window, and modules are ordered CPU, Memory, Network, Disk, GPU, Sensors, Battery, Accessories.
- Page titles moved to a top bar, and curves span the window and grow with it.
- Process lists show app icons, and settings are grouped.
- Combined dropdown: selecting a row opens its details beside the dropdown.
- A minimized window stops the readings only its page uses.
- The Overview no longer scans processes or per-app traffic as often.

### Fixed

- Reworked drag-to-reorder for module chips, to address chips that could not be dragged on macOS 15.
- Reopening a minimized window from the Dock returns to the same page.
- Temperature was blank on the CPU and GPU pages.

## [0.4.0] - 2026-11-02

### Added

- Battery levels for devices on Logitech wireless receivers, such as LIGHTSPEED mice, with no extra permission. Paired devices that are asleep or off are listed as not connected.

### Changed

- "Bluetooth" is now "Accessories", with one row per device.
- Module pages and the Alerts page use a single column.
- Dropdown actions moved from a footer to the title row.
- Numbers and units are consistently separated by a space.

### Removed

- Pausing monitoring.
- GPU frame rate and per-engine readings.
- The accessory battery curve and time range on the Accessories page.

## [0.3.1] - 2026-11-01

### Changed

- Each module has its own soft color, used in the sidebar, Overview, module pages, dropdowns and settings. Battery and accessories stay neutral unless charging or low.
- Chart fills use the page's module color in light mode.

## [0.3.0] - 2026-11-01

### Changed

- New monochrome design, with light mode as the primary appearance. Spacing and hairlines replace cards and borders.
- Charts are smooth curves. Red marks alerts, yellow marks elevated values, and normal states are uncolored.
- A title bar holds each page's controls, including process search (⌘K), and the sidebar is a column of icons.
- The Overview is a 4×2 grid with the top CPU and memory apps.
- The combined dropdown lists all modules and enlarges the first one in the menu bar.
- Alert rules are edited only on the Alerts page.

## [0.2.1] - 2026-11-01

### Added

- A Menu Bar settings page for the display mode and the combined dropdown's contents.

### Changed

- Panels and cards lose their borders, and the interface uses the system font with monospaced digits.
- Dropdowns and Overview cards use area charts, and level bars replace dot meters.
- Modules are colored throughout the interface.
- The combined dropdown is a grouped list with the busiest app and what is preventing sleep.

### Fixed

- The window controls are vertically centered in the title bar.
- Disk read, upload and CPU load readings are no longer truncated.

## [0.2.0] - 2026-11-01

### Changed

- New console design with solid surfaces in place of glass. Each module has a color, and green, yellow and red indicate state only.
- Pages open with a large reading and a chart with value and time axes.
- The Overview is a 3×3 grid of cards.
- All eight module dropdowns use the new layout.

### Added

- Recent per-core activity on the CPU page, and a latency trend on the Network page.

## [0.1.0] - 2026-10-26

Initial release, with menu bar widgets and dropdowns for CPU, GPU, memory, network, disk, battery, Bluetooth devices and sensors, plus a process list, alerts, keep-awake and animated menu bar characters.

[Unreleased]: https://github.com/Cocojcc/Rin/compare/v0.6.3...HEAD
[0.6.3]: https://github.com/Cocojcc/Rin/releases/tag/v0.6.3
[0.6.2]: https://github.com/Cocojcc/Rin/releases/tag/v0.6.2
[0.6.1]: https://github.com/Cocojcc/Rin/releases/tag/v0.6.1
[0.6.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.6.0
[0.5.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.5.0
[0.4.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.4.0
[0.3.1]: https://github.com/Cocojcc/Rin/releases/tag/v0.3.1
[0.3.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.3.0
[0.2.1]: https://github.com/Cocojcc/Rin/releases/tag/v0.2.1
[0.2.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.2.0
[0.1.0]: https://github.com/Cocojcc/Rin/releases/tag/v0.1.0
