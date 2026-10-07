import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import SnapCore

enum SettingsTab: Hashable {
    case general, shortcuts, layouts, excluded
}

/// Live state that isn't a preference (permission, hotkey conflicts, recording, selected tab).
final class RuntimeStatus: ObservableObject {
    @Published var isTrusted = AccessibilityPermission.isTrusted
    @Published var unavailableHotKeys: Set<HotKeyTarget> = []
    @Published var isRecordingShortcut = false
    @Published var selectedTab: SettingsTab = .general
}

/// Things Settings can ask the app to do.
struct SettingsActions {
    var saveLayout: (String) -> Void
    var applyLayout: (SavedLayout) -> Void
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus
    let actions: SettingsActions

    var body: some View {
        TabView(selection: $status.selectedTab) {
            GeneralSettingsView(settings: settings, status: status)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutSettingsView(settings: settings, status: status)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            LayoutSettingsView(settings: settings, status: status, actions: actions)
                .tabItem { Label("Layouts", systemImage: "rectangle.3.group") }
                .tag(SettingsTab.layouts)
            ExcludedAppsView(settings: settings)
                .tabItem { Label("Excluded Apps", systemImage: "nosign") }
                .tag(SettingsTab.excluded)
        }
        .frame(width: 560, height: 600)
        .tint(.red)
    }
}

/// Recorder bound to any hotkey target, with the "already taken by macOS" warning.
private struct HotKeyField: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus
    let target: HotKeyTarget

    var body: some View {
        HStack(spacing: 6) {
            if status.unavailableHotKeys.contains(target) && settings.hotKeysEnabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This shortcut is already used by macOS or another app.")
            }
            ShortcutRecorder(combo: Binding(get: { settings.combo(for: target) },
                                            set: { settings.assign($0, to: target) })) { recording in
                status.isRecordingShortcut = recording
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    if status.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            AccessibilityPermission.requestWithSystemPrompt()
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }
                Toggle("Launch RED SNAPPER at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Layout") {
                LabeledContent("Window gap") {
                    HStack {
                        Slider(value: $settings.gap, in: 0...40, step: 1)
                            .frame(width: 200)
                        Stepper(value: $settings.gap, in: 0...40, step: 1) {
                            Text("\(Int(settings.gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Text("Space between snapped windows and between windows and the screen edges. The menu bar and Dock are always respected.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                Toggle("Keyboard shortcuts", isOn: $settings.hotKeysEnabled)
                Toggle("Press again to cycle sizes (½ → ⅔ → ⅓)", isOn: $settings.cycleSizes)
                Toggle("Continue onto the next display at the screen edge", isOn: $settings.hopDisplays)
                Text("With both on, pressing ⌃⌥← on a window already at the left third moves it to the right half of the display on your left.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Mouse") {
                Toggle("Drag to snap", isOn: $settings.dragToSnapEnabled)
                Text("Drag a window by its title bar to a screen edge or corner. Left/right edges → halves, corners → quarters, top edge → maximize, bottom edge → thirds. Drag a snapped window away to get its old size back.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Right-click a title bar for the snap menu", isOn: $settings.titleBarMenuEnabled)
                Text("Right-click an empty spot in any window's title bar to pick a layout with the mouse.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Tip: macOS has its own edge tiling. RED SNAPPER overrides it, but for the smoothest drags turn off **System Settings › Desktop & Dock › Drag windows to screen edges to tile**.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Desktop & Dock Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). Move RED SNAPPER to /Applications and try again."
        }
        if service.status == .requiresApproval {
            loginError = "Approve RED SNAPPER in System Settings › General › Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
        let actual = service.status == .enabled || service.status == .requiresApproval
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(HotKeyAction.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.actions) { action in
                            LabeledContent(action.displayName) {
                                HotKeyField(settings: settings, status: status, target: .action(action))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("Click a shortcut to change it. Esc cancels, Delete clears.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { settings.resetBindings() }
            }
            .padding([.horizontal, .bottom], 16)
        }
    }
}

// MARK: - Layouts

private struct LayoutSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus
    let actions: SettingsActions
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Layout name", text: $newName, prompt: Text("e.g. Coding, Music, Email"))
                        .labelsHidden()
                        .onSubmit(save)
                    Button("Save Current Layout", action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Saves where every visible window is, on every display. Restoring puts the same apps' windows back (matching documents by title) — apps that aren't open are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Saved Layouts") {
                if settings.layouts.isEmpty {
                    Text("No layouts yet.").foregroundStyle(.secondary)
                }
                ForEach(settings.layouts) { layout in
                    LayoutRow(settings: settings, status: status, layout: layout, actions: actions)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        actions.saveLayout(name)
        newName = ""
    }
}

private struct LayoutRow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: RuntimeStatus
    let layout: SavedLayout
    let actions: SettingsActions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: Binding(
                    get: { layout.name },
                    set: { newValue in
                        if let i = settings.layouts.firstIndex(where: { $0.id == layout.id }) {
                            settings.layouts[i].name = newValue
                        }
                    }))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Text("\(layout.windows.count) window\(layout.windows.count == 1 ? "" : "s") · \(layout.appNames.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HotKeyField(settings: settings, status: status, target: .layout(layout.id))
            Button("Restore") { actions.applyLayout(layout) }
            Button(role: .destructive) {
                settings.layouts.removeAll { $0.id == layout.id }
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .help("Delete layout")
        }
    }
}

// MARK: - Excluded apps

private struct ExcludedAppsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Text("RED SNAPPER ignores these apps completely: no shortcuts, drag-to-snap, title-bar menu, 4-up grid or layouts. Useful for games, full-screen tools and apps that fight resizing. You can also toggle the current app from the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Menu("Add Running App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                if let id = app.bundleIdentifier { settings.setExcluded(id, true) }
                            }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…", action: chooseApp)
                }
            }

            Section("Excluded") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps.").foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button { settings.setExcluded(bundleID, false) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop excluding")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !settings.isExcluded($0.bundleIdentifier) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { settings.setExcluded(id, true) }
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                Text(bundleID).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
