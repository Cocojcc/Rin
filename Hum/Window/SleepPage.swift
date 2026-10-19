import AppKit
import SwiftUI

/// Keep-awake on top, then everything currently holding the Mac awake.
struct SleepPage: View {
    var keepAwake = KeepAwake.shared
    var settings = SettingsStore.shared
    @State private var blockers: [SleepBlocker] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.sleep)
            Section(title: L10n.Sleep.keepAwake) {
                VStack(spacing: 0) {
                    ticking { status($0) }
                    ModeChips(keepAwake: keepAwake)
                        .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
                    toggleRow(L10n.Sleep.keepDisplay, isOn: Binding(
                        get: { settings.prefs.sleep.keepDisplay },
                        set: { settings.prefs.sleep.keepDisplay = $0; keepAwake.preferencesChanged() }))
                    toggleRow(L10n.Sleep.lowBattery(Format.percent(KeepAwake.lowBattery)), isOn: Binding(
                        get: { settings.prefs.sleep.offWhenLow },
                        set: { settings.prefs.sleep.offWhenLow = $0 }))
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            Section(title: L10n.Sleep.blockers) {
                ticking { now in
                    VStack(spacing: 0) {
                        DividedRows {
                            if keepAwake.isOn, let started = keepAwake.started {
                                BlockerRow(name: L10n.App.name, detail: detail(L10n.Sleep.keepAwake, display: keepAwake.holdsDisplay),
                                           held: now.timeIntervalSince(started)) { AppMark(size: 18) }
                            }
                            ForEach(blockers) { b in blockerRow(b, now: now) }
                        }
                        if !keepAwake.isOn && blockers.isEmpty {
                            Text(L10n.Sleep.nothing).ui(13).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                }
            }
        }
        .task {
            // Assertions come and go with media playback and syncing; re-read while the page is up.
            while !Task.isCancelled {
                blockers = SleepBlocker.read()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onAppear { if RenderContext.offscreen { blockers = SleepBlocker.read() } }
    }

    /// Redraws the content every second (the keep-awake clock and the durations).
    @ViewBuilder private func ticking<Content: View>(@ViewBuilder _ content: @escaping (Date) -> Content) -> some View {
        if RenderContext.offscreen {
            content(Date())
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
        }
    }

    // MARK: Keep awake

    @ViewBuilder private func status(_ now: Date) -> some View {
        HStack(spacing: 16) {
            LineIcon(d: Icons.cup, size: 22, lineWidth: 1.5)
                .foregroundStyle(keepAwake.isOn ? Theme.ok : Theme.sub)
                .frame(width: 48, height: 48)
                .background(Circle().fill(keepAwake.isOn ? Theme.okBg : Theme.well))
                .accessibilityHidden(true)
            if keepAwake.isOn {
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption).ui(12).foregroundStyle(Theme.sub)
                    Text(Format.hms(clockSeconds(now))).ui(36, 500).kerning(-1.08).frame(height: 40).monospacedDigit()
                    Text(endLine).ui(12).foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                pillButton(L10n.Sleep.turnOff, fill: Theme.well, text: Theme.text) { keepAwake.stop() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.Sleep.offTitle).ui(15, 500)
                    Text(L10n.Sleep.offSub).ui(12).foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                AccentPillButton(title: L10n.Sleep.turnOn) { keepAwake.start(keepAwake.mode) }
            }
        }
        .padding(14)
    }

    private var timed: Bool { keepAwake.endsAt != nil }

    private var caption: String { timed ? L10n.Sleep.remaining : L10n.Sleep.awake }

    private func clockSeconds(_ now: Date) -> Double {
        if let end = keepAwake.endsAt { return max(0, end.timeIntervalSince(now)) }
        return max(0, now.timeIntervalSince(keepAwake.started ?? now))
    }

    private var endLine: String {
        if let end = keepAwake.endsAt { return L10n.Sleep.endsAt(Format.time(end)) }
        return keepAwake.mode == .whileCharging ? L10n.Sleep.endsUnplugged : L10n.Sleep.untilOff
    }

    private func pillButton(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(12, 500).foregroundStyle(text)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title).ui(13)
            Spacer(minLength: 0)
            HumSwitch(isOn: isOn, label: title)
        }
        .frame(height: 42)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .padding(.horizontal, 14)
    }

    // MARK: Blockers

    private func detail(_ reason: String, display: Bool) -> String {
        reason + " · " + (display ? L10n.Sleep.preventsDisplay : L10n.Sleep.preventsSystem)
    }

    @ViewBuilder private func blockerRow(_ b: SleepBlocker, now: Date) -> some View {
        let held = now.timeIntervalSince(b.since)
        switch b.owner {
        case .app(let app):
            let name = app.localizedName ?? ""
            BlockerRow(name: name, detail: detail(b.reason, display: b.display), held: held,
                       open: { app.activate() }, openLabel: L10n.Sleep.openNamed(name)) {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                } else {
                    LetterTile(name: name)
                }
            }
        case .process(let name, _):
            BlockerRow(name: name, detail: detail(b.reason, display: b.display), held: held) { LetterTile(name: name) }
        case .system:
            BlockerRow(name: L10n.Sleep.macOS, detail: detail(b.reason, display: b.display), held: held, dimmed: true) {
                LineIcon(d: Icons.gear, size: 12, lineWidth: 1.3)
                    .foregroundStyle(Theme.sub)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.well))
            }
        }
    }

    /// "32 分钟" / "1 小时 46 分" / "4 天 3 小时".
    static func held(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return L10n.Sleep.underMinute }
        if m < 60 { return L10n.Sleep.minutes(m) }
        if m < 1440 { return L10n.Sleep.hoursMinutes(m / 60, m % 60) }
        return L10n.Sleep.daysHours(m / 1440, (m % 1440) / 60)
    }
}

private struct BlockerRow<Icon: View>: View {
    var name: String
    var detail: String
    var held: TimeInterval
    var open: (() -> Void)? = nil
    var openLabel = ""
    var dimmed = false
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                icon.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).ui(13).foregroundStyle(dimmed ? Theme.sub : Theme.text).lineLimit(1)
                    Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 12) {
                if let open {
                    Button(action: open) {
                        Text(L10n.Sleep.open).ui(12).foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(Theme.well))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openLabel)
                }
                Text(SleepPage.held(held)).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Accent capsule button ("开启").
private struct AccentPillButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).ui(12, 500).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(Theme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The seven "how long" chips, four to a row, the chosen one under a sliding glass thumb.
private struct ModeChips: View {
    var keepAwake: KeepAwake
    @State private var customOpen = false
    @State private var customTime = Date().addingTimeInterval(2 * 3600)

    private enum Choice: Hashable {
        case preset(KeepAwake.Mode)
        case custom
    }

    var body: some View {
        let chosen = choice(keepAwake.mode)
        // Four to a row, three when the window is narrow.
        EvenGrid(maxColumns: 4, minWidth: 128, hSpacing: 6, vSpacing: 6) {
            ForEach(KeepAwake.Mode.presets, id: \.self) { mode in
                chip(icon(mode), title(mode), on: chosen == .preset(mode)) { keepAwake.select(mode); start() }
            }
            chip(Icons.sliders, L10n.Sleep.modeCustom, on: chosen == .custom) { customOpen = true }
                .popover(isPresented: $customOpen, arrowEdge: .bottom) { customPicker }
        }
        .slidingThumb(chosen) { GlassThumb() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sleep.modesLabel)
    }

    /// Picking a chip starts keeping awake right away.
    private func start() {
        if !keepAwake.isOn { keepAwake.start(keepAwake.mode) }
    }

    private func choice(_ mode: KeepAwake.Mode) -> Choice {
        if case .custom = mode { return .custom }
        return .preset(mode)
    }

    private func icon(_ mode: KeepAwake.Mode) -> String {
        switch mode {
        case .indefinite: return Icons.infinity
        case .minutes: return Icons.clock
        case .untilHour: return Icons.sunset
        case .whileCharging: return Icons.plug
        case .custom: return Icons.sliders
        }
    }

    private func title(_ mode: KeepAwake.Mode) -> String {
        switch mode {
        case .indefinite: return L10n.Sleep.modeIndefinite
        case .minutes(let m): return m == 60 ? L10n.Sleep.modeHour : L10n.Sleep.modeMinutes(m)
        case .untilHour(let h):
            let date = KeepAwake.next(hour: h, minute: 0, after: Date())
            return L10n.Sleep.modeUntil(Format.time(date))
        case .whileCharging: return L10n.Sleep.modeCharging
        case .custom: return L10n.Sleep.modeCustom
        }
    }

    private func chip(_ d: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        ModeChip(d: d, title: title, on: on, action: action)
    }

    private var customPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Sleep.customUntil).ui(12, 500).foregroundStyle(Theme.sub)
            DatePicker(L10n.Sleep.customUntil, selection: $customTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            PrimaryButton(title: L10n.Sleep.start, height: 28, radius: 8, fontSize: 12) {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: customTime)
                let end = KeepAwake.next(hour: parts.hour ?? 0, minute: parts.minute ?? 0, after: Date())
                keepAwake.start(.custom(end))
                customOpen = false
            }
        }
        .padding(14)
        .frame(width: 200)
    }
}

private struct ModeChip: View {
    var d: String
    var title: String
    var on: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LineIcon(d: d, size: 14, lineWidth: 1.4).foregroundStyle(Theme.sub)
                Text(title).ui(13, on ? 500 : 400).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                if !on { Capsule().fill(hovering ? Theme.lgHover : Theme.panel) }
            }
            .hoverAnimation(hovering)
            .thumbAnchor(on)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
