import AppKit
import SwiftUI

/// Keep-awake on top (its clock in the accent while on), how long and its two options on rows,
/// then everything currently holding the Mac awake.
struct SleepPage: View {
    var keepAwake = KeepAwake.shared
    var settings = SettingsStore.shared
    @State private var blockers: [SleepBlocker] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(title: L10n.Sidebar.sleep)
            ticking { status($0) }.padding(.top, 30)
            VStack(spacing: 0) {
                DividedRows {
                    SettingsRow(title: L10n.Sleep.duration) { DurationControl(keepAwake: keepAwake) }
                    SettingsRow(title: L10n.Sleep.keepDisplay) {
                        RinSwitch(isOn: Binding(get: { settings.prefs.sleep.keepDisplay },
                                                set: { settings.prefs.sleep.keepDisplay = $0; keepAwake.preferencesChanged() }), label: L10n.Sleep.keepDisplay)
                    }
                    let low = L10n.Sleep.lowBattery(Format.percent(KeepAwake.lowBattery))
                    SettingsRow(title: low) {
                        RinSwitch(isOn: Binding(get: { settings.prefs.sleep.offWhenLow }, set: { settings.prefs.sleep.offWhenLow = $0 }), label: low)
                    }
                }
            }
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 22)
            ticking { now in
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Sleep.blockers) { Text(L10n.Sleep.blockerCount(blockers.count + (keepAwake.isOn ? 1 : 0))) }
                    VStack(spacing: 0) {
                        DividedRows {
                            if keepAwake.isOn, let started = keepAwake.started {
                                BlockerRow(name: L10n.App.name, detail: detail(L10n.Sleep.keepAwake, display: keepAwake.holdsDisplay),
                                           held: now.timeIntervalSince(started))
                            }
                            ForEach(blockers) { b in blockerRow(b, now: now) }
                        }
                    }
                    if !keepAwake.isOn && blockers.isEmpty {
                        Text(L10n.Sleep.nothing).ui(14).foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
            .padding(.top, 26)
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

    private func status(_ now: Date) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SmallLabel(text: keepAwake.isOn ? caption : L10n.Sleep.keepAwake)
                if keepAwake.isOn {
                    BigValue(value: Format.hms(clockSeconds(now)), size: 44, color: Theme.accent).padding(.top, 10)
                    Text(endLine).ui(12).foregroundStyle(Theme.sub).padding(.top, 12)
                } else {
                    BigValue(value: L10n.Sleep.offShort, size: 44).padding(.top, 10)
                    Text(L10n.Sleep.offSub).ui(12).foregroundStyle(Theme.sub).padding(.top, 12)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            RoundAction(on: keepAwake.isOn) {
                if keepAwake.isOn { keepAwake.stop() } else { keepAwake.start(keepAwake.mode) }
            }
        }
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
                       open: { app.activate() }, openLabel: L10n.Sleep.openNamed(name))
        case .process(let name, _):
            BlockerRow(name: name, detail: detail(b.reason, display: b.display), held: held)
        case .system:
            BlockerRow(name: L10n.Sleep.macOS, detail: detail(b.reason, display: b.display), held: held)
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

/// One holder: its name and why on one line, how long it has held on, Open for apps.
private struct BlockerRow: View {
    var name: String
    var detail: String
    var held: TimeInterval
    var open: (() -> Void)? = nil
    var openLabel = ""

    var body: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name).ui(14).lineLimit(1).fixedSize()
                Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(SleepPage.held(held)).ui(14, 500).lineLimit(1).fixedSize()
            // Holds its column even without a button, so the times line up.
            ZStack(alignment: .trailing) {
                Color.clear
                if let open { IconAction(d: Icons.openExternal, label: openLabel, size: 28, action: open) }
            }
            .frame(width: 52, height: 28)
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }
}

/// Keep-awake's own button: a round grey stop (a small square) while on, a start (a triangle) while off.
private struct RoundAction: View {
    var on: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if on {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).frame(width: 12, height: 12)
                } else {
                    SVGShape(d: Icons.play, viewBox: CGSize(width: 16, height: 16)).frame(width: 14, height: 14).offset(x: 1)
                }
            }
            .foregroundStyle(Theme.text)
            .frame(width: 40, height: 40)
            .background(Circle().fill(hovering ? Theme.chip : Theme.raise))
            .hoverAnimation(hovering)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(on ? L10n.Sleep.turnOffA11y : L10n.Sleep.turnOnA11y)
        .accessibilityLabel(on ? L10n.Sleep.turnOffA11y : L10n.Sleep.turnOnA11y)
    }
}

/// How long to keep awake, as one segmented row; the last segment picks a time in a popover.
private struct DurationControl: View {
    var keepAwake: KeepAwake
    @State private var customOpen = false
    @State private var customTime = Date().addingTimeInterval(2 * 3600)

    private enum Choice: Hashable {
        case preset(KeepAwake.Mode)
        case custom
    }

    var body: some View {
        let chosen = choice(keepAwake.mode)
        HStack(spacing: 2) {
            ForEach(KeepAwake.Mode.presets, id: \.self) { mode in
                segment(title(mode), on: chosen == .preset(mode)) { keepAwake.select(mode); start() }
            }
            segment(L10n.Sleep.modeCustomEllipsis, on: chosen == .custom) { customOpen = true }
                .popover(isPresented: $customOpen, arrowEdge: .bottom) { customPicker }
        }
        .slidingThumb(chosen) { GlassThumb() }
        .padding(3)
        .background(GlassTrack())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sleep.modesLabel)
    }

    /// Picking a duration starts keeping awake right away.
    private func start() {
        if !keepAwake.isOn { keepAwake.start(keepAwake.mode) }
    }

    private func choice(_ mode: KeepAwake.Mode) -> Choice {
        if case .custom = mode { return .custom }
        return .preset(mode)
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

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(13).lineLimit(1)
                .foregroundStyle(on ? Theme.text : Theme.sub)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .thumbAnchor(on)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var customPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Sleep.customUntil).ui(12, 500).foregroundStyle(Theme.sub)
            DatePicker(L10n.Sleep.customUntil, selection: $customTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            PrimaryButton(title: L10n.Sleep.start, height: 28, radius: 7, fontSize: 12) {
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
