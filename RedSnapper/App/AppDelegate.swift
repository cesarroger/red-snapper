import AppKit
import SwiftUI
import Combine
import SnapCore

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication.delegate is weak; keep ours alive for the life of the run loop.
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private lazy var windowManager = WindowManager(settings: settings)
    private var hotKeys: HotKeyManager!
    private var menuBar: MenuBarController!
    private lazy var dragSnap = DragSnapController(windowManager: windowManager, settings: settings)
    private lazy var titleBarMenu = TitleBarMenuController(settings: settings) { [weak self] window, point in
        self?.showPicker(for: window, at: point)
    }
    private let picker = SnapPickerPanel()
    private let hud = HUD()
    private let updater = Updater()

    private let status = RuntimeStatus()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var trustTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeys = HotKeyManager { [weak self] target in self?.trigger(target) }
        menuBar = MenuBarController(settings: settings, handlers: .init(
            perform: { [weak self] in self?.windowManager.perform($0) },
            applyLayout: { [weak self] in self?.applyLayout($0) },
            saveLayout: { [weak self] in self?.promptSaveLayout() },
            openSettings: { [weak self] in self?.showSettings(tab: $0) },
            openOnboarding: { [weak self] in self?.showOnboarding() },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }))
        updater.start()

        // Re-register hotkeys whenever bindings, layout shortcuts or the master toggle change,
        // and suspend them while a shortcut is being recorded in Settings.
        // (`@Published` emits before the property is set, so use the emitted values.)
        settings.$bindings.combineLatest(settings.$layouts, settings.$hotKeysEnabled, status.$isRecordingShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] bindings, layouts, enabled, recording in
                var all: [HotKeyTarget: KeyCombo] = [:]
                for (action, combo) in bindings { all[.action(action)] = combo }
                for layout in layouts { if let k = layout.hotKey { all[.layout(layout.id)] = k } }
                self?.applyHotKeys(all, enabled: enabled && !recording, reportConflicts: !recording)
            }
            .store(in: &cancellables)

        settings.$dragToSnapEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.updateDragSnap(enabled: enabled) }
            .store(in: &cancellables)

        settings.$titleBarMenuEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.updateTitleBarMenu(enabled: enabled) }
            .store(in: &cancellables)

        if AccessibilityPermission.isTrusted {
            accessibilityGranted()
        } else {
            showOnboarding()
        }
    }

    private func trigger(_ target: HotKeyTarget) {
        switch target {
        case .action(let action):
            windowManager.perform(action)
        case .layout(let id):
            if let layout = settings.layouts.first(where: { $0.id == id }) { applyLayout(layout) }
        }
    }

    private func applyHotKeys(_ hotKeys: [HotKeyTarget: KeyCombo], enabled: Bool, reportConflicts: Bool) {
        if enabled {
            self.hotKeys.register(hotKeys)
            status.unavailableHotKeys = self.hotKeys.failed
        } else {
            self.hotKeys.unregisterAll()
            if reportConflicts { status.unavailableHotKeys = [] }
        }
    }

    /// Global mouse monitors and event taps only see other apps' events when trusted, so these
    /// start after permission is granted (and restart if toggled meanwhile).
    private func updateDragSnap(enabled: Bool? = nil) {
        if (enabled ?? settings.dragToSnapEnabled) && AccessibilityPermission.isTrusted {
            dragSnap.start()
        } else {
            dragSnap.stop()
        }
    }

    private func updateTitleBarMenu(enabled: Bool? = nil) {
        if (enabled ?? settings.titleBarMenuEnabled) && AccessibilityPermission.isTrusted {
            titleBarMenu.start()
        } else {
            titleBarMenu.stop()
            picker.close()
        }
    }

    /// Called once Accessibility is available; starts features that depend on it.
    private func accessibilityGranted() {
        status.isTrusted = true
        updateDragSnap()
        updateTitleBarMenu()
        windowManager.tracker.start()
        if let window = onboardingWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { window.close() }
        }
    }

    /// Launching the app again while it's running (Finder, Spotlight) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(tab: nil)
        return true
    }

    // MARK: - Snap picker

    private func showPicker(for window: AXWindow, at point: NSPoint) {
        let appName = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "Window"
        picker.show(at: point, appName: appName) { [weak self] action in
            self?.windowManager.perform(action, on: window, allowCycling: false)
        }
    }

    // MARK: - Layouts

    private func applyLayout(_ layout: SavedLayout) {
        windowManager.applyLayout(layout) { [weak self] result in
            var detail: String?
            if !result.missingApps.isEmpty {
                detail = "Not running: " + result.missingApps.prefix(4).joined(separator: ", ")
                    + (result.missingApps.count > 4 ? "…" : "")
            }
            let message = result.restored == result.total
                ? "“\(layout.name)” restored"
                : "“\(layout.name)”: \(result.restored) of \(result.total) windows"
            self?.hud.show(message, detail: detail, symbol: "rectangle.3.group.fill")
        }
    }

    private func saveLayout(named name: String) {
        windowManager.captureLayout(named: name) { [weak self] layout in
            guard let self else { return }
            guard !layout.windows.isEmpty else {
                self.hud.show("No windows to save", symbol: "exclamationmark.triangle.fill")
                return
            }
            // Saving under an existing name replaces it (keeping its shortcut).
            if let i = self.settings.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                var updated = layout
                updated.id = self.settings.layouts[i].id
                updated.hotKey = self.settings.layouts[i].hotKey
                self.settings.layouts[i] = updated
            } else {
                self.settings.layouts.append(layout)
            }
            self.hud.show("Saved “\(name)”", detail: "\(layout.windows.count) windows · \(layout.appNames.count) apps",
                          symbol: "rectangle.3.group.fill")
        }
    }

    private func promptSaveLayout() {
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "Saves the position of every visible window on every display."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Layout name (e.g. Coding)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        saveLayout(named: name.isEmpty ? "Layout \(settings.layouts.count + 1)" : name)
    }

    // MARK: - Windows

    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(status: status)))
            window.title = "RED SNAPPER"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)

        if trustTimer == nil && !AccessibilityPermission.isTrusted {
            // Poll until the user flips the switch in System Settings.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AccessibilityPermission.isTrusted else { return }
                timer.invalidate()
                self?.trustTimer = nil
                self?.accessibilityGranted()
            }
        }
    }

    private func showSettings(tab: SettingsTab?) {
        if settingsWindow == nil {
            let actions = SettingsActions(saveLayout: { [weak self] in self?.saveLayout(named: $0) },
                                          applyLayout: { [weak self] in self?.applyLayout($0) },
                                          updater: updater)
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, status: status, actions: actions))
            let window = NSWindow(contentViewController: hosting)
            window.title = "RED SNAPPER Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        if let tab { status.selectedTab = tab }
        status.isTrusted = AccessibilityPermission.isTrusted
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
