import AppKit
import SnapCore

/// The status-bar item and its menu.
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Handlers {
        var perform: (HotKeyAction) -> Void
        var applyLayout: (SavedLayout) -> Void
        var saveLayout: () -> Void
        var openSettings: (SettingsTab) -> Void
        var openOnboarding: () -> Void
        var checkForUpdates: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: AppSettings
    private let handlers: Handlers

    init(settings: AppSettings, handlers: Handlers) {
        self.settings = settings
        self.handlers = handlers
        super.init()

        if let button = statusItem.button {
            // Not a template image, so macOS keeps it red instead of tinting it black/white.
            let red = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "RED SNAPPER")?
                .withSymbolConfiguration(red)
            button.toolTip = "RED SNAPPER"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild every time the menu opens so checkmarks, shortcuts and permission state are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "RED SNAPPER", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !AccessibilityPermission.isTrusted {
            menu.addItem(item("⚠︎ Grant Accessibility Access…", #selector(showOnboarding)))
        }
        menu.addItem(.separator())

        menu.addItem(snapSubmenu())
        menu.addItem(layoutsSubmenu())
        menu.addItem(.separator())

        // Status menus don't activate RED SNAPPER, so the frontmost app is still the user's app.
        if let front = NSWorkspace.shared.frontmostApplication, let bundleID = front.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let ignore = item("Ignore \(front.localizedName ?? "This App")", #selector(toggleIgnoreFrontApp(_:)))
            ignore.representedObject = bundleID
            ignore.state = settings.isExcluded(bundleID) ? .on : .off
            menu.addItem(ignore)
        }

        let hotKeys = item("Keyboard Shortcuts", #selector(toggleHotKeys))
        hotKeys.state = settings.hotKeysEnabled ? .on : .off
        menu.addItem(hotKeys)

        let drag = item("Drag to Snap", #selector(toggleDrag))
        drag.state = settings.dragToSnapEnabled ? .on : .off
        menu.addItem(drag)

        let titleBar = item("Title Bar Snap Menu", #selector(toggleTitleBar))
        titleBar.state = settings.titleBarMenuEnabled ? .on : .off
        menu.addItem(titleBar)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("Quit RED SNAPPER", #selector(quit), key: "q"))
    }

    private func snapSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Snap Focused Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (i, group) in HotKeyAction.groups.enumerated() {
            if i > 0 { submenu.addItem(.separator()) }
            for action in group.actions {
                var label = action.displayName
                if let combo = settings.bindings[action] { label += "\t\(combo.displayString)" }
                let mi = item(label, #selector(runAction(_:)))
                mi.representedObject = action.rawValue
                submenu.addItem(mi)
            }
        }
        parent.submenu = submenu
        return parent
    }

    private func layoutsSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if settings.layouts.isEmpty {
            let empty = NSMenuItem(title: "No saved layouts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for layout in settings.layouts {
            var label = layout.name
            if let combo = layout.hotKey { label += "\t\(combo.displayString)" }
            let mi = item(label, #selector(applyLayout(_:)))
            mi.representedObject = layout.id.uuidString
            mi.toolTip = layout.appNames.joined(separator: ", ")
            submenu.addItem(mi)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Save Current Layout…", #selector(saveLayout)))
        submenu.addItem(item("Manage Layouts…", #selector(manageLayouts)))
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotKeyAction(rawValue: raw) else { return }
        // Let the menu finish closing so focus is back on the target app's window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.handlers.perform(action) }
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = settings.layouts.first(where: { $0.id.uuidString == raw }) else { return }
        handlers.applyLayout(layout)
    }

    @objc private func toggleIgnoreFrontApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        settings.setExcluded(bundleID, !settings.isExcluded(bundleID))
    }

    @objc private func saveLayout() { handlers.saveLayout() }
    @objc private func manageLayouts() { handlers.openSettings(.layouts) }
    @objc private func toggleHotKeys() { settings.hotKeysEnabled.toggle() }
    @objc private func toggleDrag() { settings.dragToSnapEnabled.toggle() }
    @objc private func toggleTitleBar() { settings.titleBarMenuEnabled.toggle() }
    @objc private func showSettings() { handlers.openSettings(.general) }
    @objc private func showOnboarding() { handlers.openOnboarding() }
    @objc private func checkForUpdates() { handlers.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
