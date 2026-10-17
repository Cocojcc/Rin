import SwiftUI

struct MainView: View {
    var navigator = Navigator.shared
    var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 210)
            Rectangle().fill(Theme.line).frame(width: 0.5)
            PageView(page: navigator.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.content)
        }
        .frame(minWidth: 760, minHeight: 560)
        .environment(\.accent, settings.prefs.general.accent.colors)
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
    }
}

struct PageView: View {
    let page: Page

    var body: some View {
        if RenderContext.offscreen {
            // ImageRenderer can't draw scroll views.
            stack.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { stack }
                .scrollIndicators(.automatic)
                .id(page)
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 28, trailing: 28))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .overview: OverviewPage()
        case .monitor(let m):
            switch m {
            case .cpu: CPUPage()
            case .gpu: GPUPage()
            case .memory: MemoryPage()
            case .network: NetworkPage()
            case .disk: DiskPage()
            case .battery: BatteryPage()
            case .sensors: SensorsPage()
            }
        case .general: GeneralSettingsPage()
        case .menubar: MenubarSettingsPage()
        case .menubarModule(let m): MenubarModulePage(module: m)
        case .alerts: AlertsSettingsPage()
        case .about: AboutPage()
        }
    }
}

struct Sidebar: View {
    var navigator = Navigator.shared
    @Environment(\.accent) private var accent

    private let monitors: [(Page, String, String)] = [
        (.overview, Icons.overview, L10n.Sidebar.overview),
        (.monitor(.cpu), Icons.cpu, L10n.Module.cpu),
        (.monitor(.gpu), Icons.gpu, L10n.Module.gpu),
        (.monitor(.memory), Icons.memory, L10n.Module.memory),
        (.monitor(.network), Icons.network, L10n.Module.network),
        (.monitor(.disk), Icons.disk, L10n.Module.disk),
        (.monitor(.battery), Icons.battery, L10n.Module.battery),
        (.monitor(.sensors), Icons.sensors, L10n.Module.sensors),
    ]

    private let settingsPages: [(Page, String, String)] = [
        (.general, Icons.general, L10n.Sidebar.general),
        (.menubar, Icons.menubar, L10n.Sidebar.menubar),
        (.alerts, Icons.alert, L10n.Sidebar.alerts),
        (.about, Icons.about, L10n.Sidebar.about),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 32)   // traffic lights
            HStack(spacing: 10) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.App.name).font(.system(size: 14, weight: .bold))
                    Text(L10n.App.version(SystemInfo.appVersion)).font(.system(size: 11)).foregroundStyle(Theme.sub)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 18)

            sectionTitle(L10n.Sidebar.monitors)
            ForEach(monitors, id: \.0) { item($0) }
            sectionTitle(L10n.Sidebar.settings).padding(.top, 10)
            ForEach(settingsPages, id: \.0) { item($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.side)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private func item(_ entry: (Page, String, String)) -> some View {
        let on = navigator.page.sidebarPage == entry.0
        return Button {
            navigator.page = entry.0
        } label: {
            HStack(spacing: 10) {
                IconChip(d: entry.1, size: 22, iconSize: 13, radius: 6,
                         color: on ? accent.onAccent : Theme.text,
                         fill: on ? accent.accent : Theme.chip, lineWidth: 1.6)
                Text(entry.2)
                    .fontWeight(on ? .semibold : .regular)
                    .foregroundStyle(on ? accent.tintText : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.leading, 5)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? accent.tint : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The app mark: three bars on an accent tile.
struct AppMark: View {
    var size: CGFloat
    @Environment(\.accent) private var accent

    var body: some View {
        LineIcon(d: Icons.appMark, size: size * 0.56, viewBox: 24, lineWidth: 2.4)
            .foregroundStyle(accent.onAccent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.265, style: .continuous).fill(accent.accent))
            .accessibilityHidden(true)
    }
}
