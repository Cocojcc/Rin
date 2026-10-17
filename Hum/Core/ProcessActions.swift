import AppKit
import Foundation
import Observation

/// Quitting processes from the lists. Apps get a normal quit (they may ask to save);
/// if the process is still there after a few seconds it is marked unresponsive and the row
/// offers Force Quit inline. System processes never get these controls.
enum ProcessActions {
    static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    @discardableResult
    static func quit(pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) { return app.terminate() }
        return kill(pid, SIGTERM) == 0
    }

    @discardableResult
    static func forceQuit(pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) { return app.forceTerminate() }
        return kill(pid, SIGKILL) == 0
    }

    static func reveal(_ process: ProcessUsage) {
        let path = process.bundlePath ?? process.executablePath
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func copyNameAndPID(_ process: ProcessUsage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(process.name) \(process.pid)", forType: .string)
    }

    static func icon(for process: ProcessUsage) -> NSImage? {
        IconCache.shared.icon(for: process)
    }
}

final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for process: ProcessUsage) -> NSImage? {
        guard let path = process.bundlePath else { return nil }
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache[path] = image
        return image
    }
}

@Observable
final class QuitCenter {
    static let shared = QuitCenter()

    enum State: Equatable {
        case quitting
        case unresponsive
    }

    struct Toast: Equatable {
        var name: String
        var freed: UInt64
        var id = UUID()
    }

    private(set) var states: [String: State] = [:]
    private(set) var toast: Toast?

    func quit(_ p: ProcessUsage) {
        guard !p.isSystem else { return }
        let pids = Set(p.pids + [p.pid])
        states[p.id] = .quitting
        ProcessActions.quit(pid: p.pid)
        // Non-app groups (helpers without a main app process) need each pid asked.
        if NSRunningApplication(processIdentifier: p.pid) == nil {
            for pid in pids where pid != p.pid { kill(pid, SIGTERM) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.states[p.id] == .quitting else { return }
            if ProcessActions.isRunning(p.pid) {
                self.states[p.id] = .unresponsive
            } else {
                self.states[p.id] = nil
                self.show(Toast(name: p.name, freed: p.memory))
            }
        }
        // Fast path: most apps are gone within a second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.states[p.id] == .quitting, !ProcessActions.isRunning(p.pid) else { return }
            self.states[p.id] = nil
            self.show(Toast(name: p.name, freed: p.memory))
        }
    }

    func askForceQuit(_ p: ProcessUsage) {
        guard !p.isSystem else { return }
        states[p.id] = .unresponsive
    }

    func forceQuit(_ p: ProcessUsage) {
        for pid in Set(p.pids + [p.pid]) { ProcessActions.forceQuit(pid: pid) }
        states[p.id] = nil
        show(Toast(name: p.name, freed: p.memory))
    }

    func cancel(_ p: ProcessUsage) {
        states[p.id] = nil
    }

    private func show(_ t: Toast) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}
