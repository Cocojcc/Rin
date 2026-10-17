import SwiftUI

/// Glass window: translucent sidebar on the left, the page on the right.
struct MainView: View {
    var navigator = Navigator.shared
    var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 200)
            PageView(page: navigator.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 600)
        .background(GlassBackground(radius: 18, material: .underWindowBackground))
        .environment(\.accent, settings.prefs.general.accent.colors)
        .ui(13)
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
        content
            .padding(EdgeInsets(top: 46, leading: 30, bottom: 30, trailing: 30))
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
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.App.name).ui(18, 600).kerning(-0.18)
                    Text(L10n.App.version(SystemInfo.appVersion)).ui(11).foregroundStyle(Theme.sub)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            sectionTitle(L10n.Sidebar.monitors)
            ForEach(monitors, id: \.0) { item($0) }
            sectionTitle(L10n.Sidebar.settings).padding(.top, 14)
            ForEach(settingsPages, id: \.0) { item($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.side)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Sidebar.label)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).ui(11, 500)
            .foregroundStyle(Theme.sub)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    private func item(_ entry: (Page, String, String)) -> some View {
        let on = navigator.page.sidebarPage == entry.0
        return Button {
            navigator.page = entry.0
        } label: {
            HStack(spacing: 10) {
                LineIcon(d: entry.1, size: 15, lineWidth: 1.5)
                Text(entry.2).ui(13, on ? 500 : 400)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Theme.text : Theme.sub)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? Theme.raised : Color.clear)
                    .raisedShadow(on)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The app mark: three bars on an ink tile.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        LineIcon(d: Icons.appMark, size: size * 0.54, viewBox: 24, lineWidth: 2.6)
            .foregroundStyle(Theme.onInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.ink))
            .accessibilityHidden(true)
    }
}
