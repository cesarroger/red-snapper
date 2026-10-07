import Foundation
import Combine
import SnapCore

/// Something a global hotkey can trigger.
enum HotKeyTarget: Hashable {
    case action(HotKeyAction)
    case layout(UUID)
}

/// Observable user preferences. Persistence lives in `PreferencesStore` (SnapCore, unit-tested).
/// Main-thread only; background work receives a `SnapContext` snapshot instead.
final class AppSettings: ObservableObject {
    private let store: PreferencesStore
    private typealias Key = PreferencesStore.Key

    /// Space in points between windows and between windows and screen edges.
    @Published var gap: Double { didSet { store.gap = gap } }
    @Published var hotKeysEnabled: Bool { didSet { store.set(hotKeysEnabled, for: Key.hotKeysEnabled) } }
    @Published var dragToSnapEnabled: Bool { didSet { store.set(dragToSnapEnabled, for: Key.dragToSnapEnabled) } }
    /// Pressing a half/third shortcut again cycles ½ → ⅔ → ⅓.
    @Published var cycleSizes: Bool { didSet { store.set(cycleSizes, for: Key.cycleSizes) } }
    /// At the end of a left/right cycle, move to the display on that side.
    @Published var hopDisplays: Bool { didSet { store.set(hopDisplays, for: Key.hopDisplays) } }
    /// Right-click a window's title bar for the snap picker.
    @Published var titleBarMenuEnabled: Bool { didSet { store.set(titleBarMenuEnabled, for: Key.titleBarMenuEnabled) } }
    /// Apps RED SNAPPER never touches (bundle identifiers).
    @Published var excludedBundleIDs: [String] { didSet { store.excludedBundleIDs = excludedBundleIDs } }
    @Published var bindings: [HotKeyAction: KeyCombo] { didSet { store.bindings = bindings } }
    @Published var layouts: [SavedLayout] { didSet { store.layouts = layouts } }

    init(defaults: UserDefaults = .standard) {
        store = PreferencesStore(defaults: defaults)
        gap = store.gap
        hotKeysEnabled = store.bool(Key.hotKeysEnabled)
        dragToSnapEnabled = store.bool(Key.dragToSnapEnabled)
        cycleSizes = store.bool(Key.cycleSizes)
        hopDisplays = store.bool(Key.hopDisplays)
        titleBarMenuEnabled = store.bool(Key.titleBarMenuEnabled)
        excludedBundleIDs = store.excludedBundleIDs
        bindings = store.bindings
        layouts = store.layouts
    }

    func resetBindings() {
        // Keep layout shortcuts unless they collide with a restored default.
        let defaults = HotKeyAction.defaultBindings
        let taken = Set(defaults.values)
        layouts = layouts.map { var l = $0; if let k = l.hotKey, taken.contains(k) { l.hotKey = nil }; return l }
        bindings = defaults
    }

    // MARK: - Shortcuts (actions + layouts share one namespace)

    func combo(for target: HotKeyTarget) -> KeyCombo? {
        switch target {
        case .action(let a): return bindings[a]
        case .layout(let id): return layouts.first { $0.id == id }?.hotKey
        }
    }

    /// Assigns `combo` to `target`, taking it away from whatever else had it.
    func assign(_ combo: KeyCombo?, to target: HotKeyTarget) {
        var newBindings = bindings
        var newLayouts = layouts
        if let combo {
            for (action, c) in newBindings where c == combo && target != .action(action) { newBindings[action] = nil }
            for i in newLayouts.indices where newLayouts[i].hotKey == combo && target != .layout(newLayouts[i].id) {
                newLayouts[i].hotKey = nil
            }
        }
        switch target {
        case .action(let a): newBindings[a] = combo
        case .layout(let id):
            if let i = newLayouts.firstIndex(where: { $0.id == id }) { newLayouts[i].hotKey = combo }
        }
        if newLayouts != layouts { layouts = newLayouts }
        if newBindings != bindings { bindings = newBindings }
    }

    // MARK: - Excluded apps

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        var ids = Set(excludedBundleIDs)
        if excluded { ids.insert(bundleID) } else { ids.remove(bundleID) }
        excludedBundleIDs = ids.sorted()
    }
}
