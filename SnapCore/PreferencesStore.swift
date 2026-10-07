import Foundation

/// Reads and writes every RED SNAPPER preference in `UserDefaults`.
/// Kept free of UI so persistence can be unit-tested against a throwaway suite.
public struct PreferencesStore {
    public let defaults: UserDefaults

    public enum Key {
        public static let gap = "gap"
        public static let hotKeysEnabled = "hotKeysEnabled"
        public static let dragToSnapEnabled = "dragToSnapEnabled"
        public static let cycleSizes = "cycleSizes"
        public static let hopDisplays = "hopDisplays"
        public static let titleBarMenuEnabled = "titleBarMenuEnabled"
        public static let excludedBundleIDs = "excludedBundleIDs"
        public static let bindings = "hotKeyBindings"
        public static let layouts = "savedLayouts"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.gap: 0.0,
            Key.hotKeysEnabled: true,
            Key.dragToSnapEnabled: true,
            Key.cycleSizes: true,
            Key.hopDisplays: true,
            Key.titleBarMenuEnabled: true,
        ])
    }

    // MARK: Scalars

    public var gap: Double {
        get { max(0, defaults.double(forKey: Key.gap)) }
        nonmutating set { defaults.set(max(0, newValue), forKey: Key.gap) }
    }

    public func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    public func set(_ value: Bool, for key: String) { defaults.set(value, forKey: key) }

    public var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [] }
        nonmutating set { defaults.set(Array(Set(newValue)).sorted(), forKey: Key.excludedBundleIDs) }
    }

    // MARK: Bindings

    /// Stored bindings override defaults per action; actions added in later versions get
    /// their default; an explicitly cleared shortcut stays cleared.
    public var bindings: [HotKeyAction: KeyCombo] {
        get {
            var merged = HotKeyAction.defaultBindings
            if let data = defaults.data(forKey: Key.bindings),
               let stored = try? JSONDecoder().decode([String: KeyCombo?].self, from: data) {
                for (raw, combo) in stored {
                    guard let action = HotKeyAction(rawValue: raw) else { continue }
                    merged[action] = combo
                }
            }
            return merged
        }
        nonmutating set {
            var stored: [String: KeyCombo?] = [:]
            for action in HotKeyAction.allCases { stored[action.rawValue] = .some(newValue[action]) }
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Key.bindings) }
        }
    }

    // MARK: Layouts

    public var layouts: [SavedLayout] {
        get {
            guard let data = defaults.data(forKey: Key.layouts) else { return [] }
            return (try? JSONDecoder().decode([SavedLayout].self, from: data)) ?? []
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Key.layouts) }
        }
    }
}
