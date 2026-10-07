import Foundation
import CoreGraphics

/// A named arrangement of app windows that can be restored later.
public struct SavedLayout: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var windows: [SavedWindow]
    public var hotKey: KeyCombo?

    public init(id: UUID = UUID(), name: String, windows: [SavedWindow], hotKey: KeyCombo? = nil) {
        self.id = id
        self.name = name
        self.windows = windows
        self.hotKey = hotKey
    }

    /// Distinct app names, in first-seen order (for display).
    public var appNames: [String] {
        var seen = Set<String>()
        return windows.compactMap { seen.insert($0.appName).inserted ? $0.appName : nil }
    }
}

public struct SavedWindow: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    /// Position among this app's windows, front to back, when saved.
    public var order: Int
    /// Stable display identifier (display UUID) the window was on.
    public var displayID: String
    /// That display's visible frame when saved (AppKit coordinates).
    public var displayVisibleFrame: CGRect
    /// The window frame (AppKit coordinates).
    public var frame: CGRect

    public init(bundleID: String, appName: String, title: String, order: Int,
                displayID: String, displayVisibleFrame: CGRect, frame: CGRect) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.order = order
        self.displayID = displayID
        self.displayVisibleFrame = displayVisibleFrame
        self.frame = frame
    }
}

/// Pairs saved windows with currently open ones.
public enum LayoutMatcher {
    public struct OpenWindow: Equatable, Sendable {
        public var id: UInt32
        public var bundleID: String
        public var title: String
        public var order: Int

        public init(id: UInt32, bundleID: String, title: String, order: Int) {
            self.id = id
            self.bundleID = bundleID
            self.title = title
            self.order = order
        }
    }

    /// Returns `savedIndex → open window id`. Exact title matches win first (so a specific
    /// document goes back to its spot); remaining windows of the same app are paired by
    /// their front-to-back order. Each open window is used at most once.
    public static func match(saved: [SavedWindow], open: [OpenWindow]) -> [Int: UInt32] {
        var result: [Int: UInt32] = [:]
        var used = Set<UInt32>()

        for (i, s) in saved.enumerated() where !s.title.isEmpty {
            if let w = open.first(where: { $0.bundleID == s.bundleID && $0.title == s.title && !used.contains($0.id) }) {
                result[i] = w.id
                used.insert(w.id)
            }
        }
        let remaining = saved.enumerated().filter { result[$0.offset] == nil }.sorted { $0.element.order < $1.element.order }
        for (i, s) in remaining {
            let candidates = open.filter { $0.bundleID == s.bundleID && !used.contains($0.id) }.sorted { $0.order < $1.order }
            if let w = candidates.first {
                result[i] = w.id
                used.insert(w.id)
            }
        }
        return result
    }
}
