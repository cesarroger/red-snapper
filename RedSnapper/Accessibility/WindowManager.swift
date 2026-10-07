import AppKit
import SnapCore

/// Applies layouts to real windows. All geometry decisions are delegated to SnapCore;
/// this type only reads/writes frames over Accessibility and converts coordinate spaces.
///
/// Threading: public entry points are called on the main thread. They snapshot screens
/// and settings into a `SnapContext`, then do every Accessibility call on `queue`, so an
/// app that is hung (AX calls block up to the messaging timeout) can never stall the UI.
final class WindowManager {
    private let settings: AppSettings
    let tracker = WindowTracker()
    let queue = DispatchQueue(label: "com.csr.RedSnapper.ax", qos: .userInteractive)

    /// Pre-snap frames for "Restore previous size", keyed by window. Confined to `queue`.
    private struct SnapRecord {
        var original: CGRect   // AX coordinates
        var snapped: CGRect    // AX coordinates, where we last put it
    }
    private var records: [CGWindowID: SnapRecord] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Entry points (main thread)

    /// Runs `action` on `window`, or on the focused window when nil. `allowCycling` is off for
    /// explicit picks (snap picker), where choosing "Left Half" should always mean left half.
    func perform(_ action: HotKeyAction, on window: AXWindow? = nil, allowCycling: Bool = true) {
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.requestWithSystemPrompt()
            return
        }
        let ctx = SnapContext.capture(settings)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = RunningApp.snapshot()

        queue.async { [self] in
            if action == .fourUpGrid {
                return tileFourUp(ctx, apps: apps, frontPID: frontPID)
            }
            guard let target = window ?? frontPID.flatMap(AXWindow.focused(pid:)) else { return beep() }
            guard !ctx.isExcluded(pid: target.pid) else { return }

            switch action {
            case .restore:
                restore(target, ctx)
            case .nextDisplay, .previousDisplay:
                moveToAdjacentDisplay(target, forward: action == .nextDisplay, ctx)
            default:
                guard let zone = action.zone else { return }
                if allowCycling {
                    snapWithCycling(target, pressed: zone, ctx)
                } else {
                    snap(target, to: zone, on: nil, ctx)
                }
            }
        }
    }

    /// Snaps a specific window into a zone on a specific display (drag-to-snap).
    /// `reasserting`: re-applying after something else (macOS tiling) moved the window, so the
    /// existing "previous size" record must be kept rather than replaced with that frame.
    /// `originalFrame`: the frame to restore to later (for a drag, where the window was before
    /// the drag started — at release it is mid-drag and possibly mid-animation).
    func snap(_ window: AXWindow, to zone: SnapZone, onScreenWithID screenID: String,
              originalFrame: CGRect? = nil, reasserting: Bool = false, completion: ((CGRect?) -> Void)? = nil) {
        let ctx = SnapContext.capture(settings)
        queue.async { [self] in
            let result = snap(window, to: zone, on: ctx.screen(withID: screenID), ctx,
                              keepOriginal: reasserting, originalFrame: originalFrame)
            if let completion { DispatchQueue.main.async { completion(result) } }
        }
    }

    /// Called when the user starts dragging a window we snapped: puts it back to its
    /// pre-snap size, keeping the title bar under the cursor.
    /// Calls back on the main thread with the restored frame (AX), or nil if nothing changed.
    func restoreSizeForDrag(_ window: AXWindow, startFrame: CGRect, cursorAX: CGPoint,
                            completion: @escaping (CGRect?) -> Void) {
        queue.async { [self] in
            guard let id = window.windowID, let record = records[id],
                  DragRestore.isUnchanged(startFrame, since: record.snapped),
                  let current = window.frame else { return DispatchQueue.main.async { completion(nil) } }
            records[id] = nil
            let target = DragRestore.frame(from: current, originalSize: record.original.size, cursor: cursorAX)
            window.setSize(target.size)
            window.setPosition(target.origin)
            DispatchQueue.main.async { completion(target) }
        }
    }

    /// Captures every visible window as a named layout.
    func captureLayout(named name: String, completion: @escaping (SavedLayout) -> Void) {
        let ctx = SnapContext.capture(settings)
        let apps = RunningApp.snapshot()
        queue.async { [self] in
            let layout = SavedLayout(name: name, windows: captureWindows(ctx, apps: apps))
            DispatchQueue.main.async { completion(layout) }
        }
    }

    struct LayoutResult {
        var restored: Int
        var total: Int
        var missingApps: [String]
    }

    func applyLayout(_ layout: SavedLayout, completion: @escaping (LayoutResult) -> Void) {
        let ctx = SnapContext.capture(settings)
        let apps = RunningApp.snapshot()
        queue.async { [self] in
            let result = apply(layout, ctx, apps: apps)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Snapping (queue)

    private func snapWithCycling(_ window: AXWindow, pressed zone: SnapZone, _ ctx: SnapContext) {
        guard !window.isFullScreen, let axFrame = window.frame else { return beep() }
        let current = ctx.converter.toAppKit(axFrame)
        guard let screen = ctx.screen(for: current) else { return beep() }

        let decision = SnapCycle.decide(pressed: zone, currentFrame: current, visibleFrame: screen.visibleFrame,
                                        gap: ctx.gap, cycleSizes: ctx.cycleSizes, hopDisplays: ctx.hopDisplays,
                                        hasDisplay: { ctx.neighbor(of: screen, $0) != nil })
        switch decision {
        case .snap(let next):
            snap(window, to: next, on: screen, ctx)
        case let .hop(direction, landing):
            snap(window, to: landing, on: ctx.neighbor(of: screen, direction), ctx)
        }
    }

    /// Snaps `window` into `zone` on `screen` (or the display it's on). Returns the resulting AX frame.
    @discardableResult
    private func snap(_ window: AXWindow, to zone: SnapZone, on screen: ScreenInfo?, _ ctx: SnapContext,
                      keepOriginal: Bool = false, originalFrame: CGRect? = nil) -> CGRect? {
        guard !window.isFullScreen, let axFrame = window.frame else { beep(); return nil }
        let current = ctx.converter.toAppKit(axFrame)
        guard let screen = screen ?? ctx.screen(for: current) else { return nil }
        let target = LayoutEngine.frame(for: zone, in: screen.visibleFrame, gap: ctx.gap, windowSize: current.size)
        return place(window, at: target, in: screen.visibleFrame, ctx, keepOriginal: keepOriginal, originalFrame: originalFrame)
    }

    /// Moves a window to the next/previous display (spatial left-to-right order, wrapping).
    /// A snapped window keeps its zone; any other window keeps its relative position and size.
    private func moveToAdjacentDisplay(_ window: AXWindow, forward: Bool, _ ctx: SnapContext) {
        guard !window.isFullScreen, let axFrame = window.frame else { return beep() }
        let current = ctx.converter.toAppKit(axFrame)
        guard let source = ctx.screen(for: current),
              let destination = ctx.adjacent(to: source, forward: forward) else { return beep() }

        if let zone = SnapZone.allCases.first(where: {
            LayoutEngine.frame(current, matches: $0, in: source.visibleFrame, gap: ctx.gap)
        }) {
            snap(window, to: zone, on: destination, ctx)
        } else {
            let target = ScreenMath.relocate(current, from: source.visibleFrame, to: destination.visibleFrame)
            place(window, at: target, in: destination.visibleFrame, ctx)
        }
    }

    /// Sets an AppKit-space frame, remembering the pre-snap frame for restore. If the window
    /// refuses the requested size (minimum/fixed size), it is re-anchored to the zone's
    /// outer edges and kept inside the visible frame.
    @discardableResult
    private func place(_ window: AXWindow, at target: CGRect, in visible: CGRect, _ ctx: SnapContext,
                       keepOriginal: Bool = false, originalFrame: CGRect? = nil) -> CGRect? {
        guard let before = window.frame else { return nil }
        let converter = ctx.converter
        let requested = window.isResizable ? target : CGRect(origin: target.origin, size: before.size)
        guard let resultAX = window.setFrame(converter.toAX(requested)) else { return nil }

        var final = resultAX
        let result = converter.toAppKit(resultAX)
        if abs(result.width - target.width) > 1 || abs(result.height - target.height) > 1 {
            let adjusted = LayoutEngine.adjust(target: target, actualSize: result.size, in: visible, gap: ctx.gap)
            window.setPosition(converter.toAX(adjusted).origin)
            final = window.frame ?? converter.toAX(adjusted)
        }

        if let id = window.windowID {
            // Keep the *first* pre-snap frame across consecutive snaps (cycling, re-snapping),
            // but start over if the user moved or resized the window by hand in between.
            let original: CGRect
            if let record = records[id], keepOriginal || DragRestore.isUnchanged(before, since: record.snapped) {
                original = record.original
            } else if let originalFrame {
                original = originalFrame
            } else {
                original = before
            }
            records[id] = SnapRecord(original: original, snapped: final)
        }
        return final
    }

    private func restore(_ window: AXWindow, _ ctx: SnapContext) {
        guard let id = window.windowID, let record = records.removeValue(forKey: id) else { return beep() }
        window.setFrame(record.original)
    }

    // MARK: - 4-up grid (queue)

    /// Tiles the (up to) four most recently used windows on the focused window's display
    /// into a 2x2 grid, most recent in the top-left. Fewer windows still fill the screen.
    private func tileFourUp(_ ctx: SnapContext, apps: [RunningApp], frontPID: pid_t?) {
        let focused = frontPID.flatMap(AXWindow.focused(pid:))
        if let focused { tracker.record(focused) }

        let screen: ScreenInfo?
        if let f = focused?.frame { screen = ctx.screen(for: ctx.converter.toAppKit(f)) }
        else { screen = ctx.screen(containing: NSEvent.mouseLocation) } // mouseLocation is thread-safe
        guard let screen else { return beep() }

        let onScreen = OnScreenWindows.current()
        var windowsByID: [CGWindowID: AXWindow] = [:]
        for app in apps where !ctx.excludedBundleIDs.contains(app.bundleID ?? "") {
            for window in AXWindow.windows(of: app.pid) {
                guard let id = window.windowID, window.isStandardWindow, !window.isMinimized, !window.isFullScreen,
                      let frame = window.frame, onScreen.isVisible(id, axFrame: frame),
                      ctx.screen(for: ctx.converter.toAppKit(frame)) == screen
                else { continue }
                windowsByID[id] = window
            }
        }

        let candidates = windowsByID.keys.map {
            GridPlanner.Candidate(id: $0, recency: tracker.recency(of: $0), zOrder: onScreen.zOrder[$0] ?? .max)
        }
        let picked = GridPlanner.pick(candidates).compactMap { windowsByID[$0] }
        guard !picked.isEmpty else { return beep() }

        for (window, zone) in zip(picked, GridPlanner.zones(forWindowCount: picked.count)) {
            snap(window, to: zone, on: screen, ctx)
        }
        // Bring all of them forward, leaving the most recent one on top and focused.
        for window in picked.reversed() { window.raise() }
        if let first = picked.first {
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: first.pid)?.activate() }
        }
    }

    // MARK: - Layouts (queue)

    private func captureWindows(_ ctx: SnapContext, apps: [RunningApp]) -> [SavedWindow] {
        let onScreen = OnScreenWindows.current()
        var entries: [(z: Int, window: SavedWindow)] = []
        for app in apps {
            guard let bundleID = app.bundleID, !ctx.excludedBundleIDs.contains(bundleID) else { continue }
            var appWindows: [(z: Int, title: String, frame: CGRect)] = []
            for window in AXWindow.windows(of: app.pid) {
                guard let id = window.windowID, window.isStandardWindow, !window.isMinimized, !window.isFullScreen,
                      let axFrame = window.frame, onScreen.isVisible(id, axFrame: axFrame) else { continue }
                appWindows.append((onScreen.zOrder[id] ?? .max, window.title ?? "", ctx.converter.toAppKit(axFrame)))
            }
            for (order, w) in appWindows.sorted(by: { $0.z < $1.z }).enumerated() {
                guard let screen = ctx.screen(for: w.frame) else { continue }
                entries.append((w.z, SavedWindow(bundleID: bundleID, appName: app.name, title: w.title, order: order,
                                                 displayID: screen.id, displayVisibleFrame: screen.visibleFrame,
                                                 frame: w.frame)))
            }
        }
        // Front-to-back across all apps, so restoring can re-create the stacking order.
        return entries.sorted { $0.z < $1.z }.map(\.window)
    }

    private func apply(_ layout: SavedLayout, _ ctx: SnapContext, apps: [RunningApp]) -> LayoutResult {
        let onScreen = OnScreenWindows.current()
        let wanted = Set(layout.windows.map(\.bundleID))
        var openWindows: [LayoutMatcher.OpenWindow] = []
        var byID: [UInt32: AXWindow] = [:]

        for app in apps {
            guard let bundleID = app.bundleID, wanted.contains(bundleID) else { continue }
            let windows = AXWindow.windows(of: app.pid).filter { $0.isStandardWindow && !$0.isFullScreen }
            // Order like when saving: visible windows front to back, then the rest (e.g. minimized).
            let ordered = windows.compactMap { w -> (Int, AXWindow, CGWindowID)? in
                guard let id = w.windowID else { return nil }
                return (onScreen.zOrder[id] ?? Int.max, w, id)
            }.sorted { $0.0 < $1.0 }
            for (order, entry) in ordered.enumerated() {
                byID[entry.2] = entry.1
                openWindows.append(.init(id: entry.2, bundleID: bundleID, title: entry.1.title ?? "", order: order))
            }
        }

        let matches = LayoutMatcher.match(saved: layout.windows, open: openWindows)
        let fallback = ctx.screens.first
        for (index, saved) in layout.windows.enumerated() {
            guard let id = matches[index], let window = byID[id],
                  let screen = ctx.screen(withID: saved.displayID) ?? fallback else { continue }
            if window.isMinimized { window.setMinimized(false) }
            let target = ScreenMath.relocate(saved.frame, from: saved.displayVisibleFrame, to: screen.visibleFrame)
            place(window, at: target, in: screen.visibleFrame, ctx)
        }
        // Re-create stacking: raise back-most first so the saved front-most window ends on top.
        for index in layout.windows.indices.reversed() {
            if let id = matches[index] { byID[id]?.raise() }
        }

        let runningBundles = Set(apps.compactMap(\.bundleID))
        var missing: [String] = []
        for w in layout.windows where !runningBundles.contains(w.bundleID) && !missing.contains(w.appName) {
            missing.append(w.appName)
        }
        return LayoutResult(restored: matches.count, total: layout.windows.count, missingApps: missing)
    }

    private func beep() {
        DispatchQueue.main.async { NSSound.beep() }
    }
}

/// A running regular app, captured on the main thread.
struct RunningApp {
    let pid: pid_t
    let bundleID: String?
    let name: String

    static func snapshot() -> [RunningApp] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != own }
            .map { RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName ?? "App") }
    }
}

/// What the window server is actually drawing, front to back.
struct OnScreenWindows {
    var zOrder: [CGWindowID: Int] = [:]
    var bounds: [CGWindowID: CGRect] = [:]

    static func current() -> OnScreenWindows {
        var result = OnScreenWindows()
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        for (i, info) in list.enumerated() where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            result.zOrder[id] = i
            if let dict = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict) { result.bounds[id] = rect }
        }
        return result
    }

    /// Stage Manager shows windows from other stages as small thumbnails that still count
    /// as "on screen" while AX keeps reporting their full-size frame. Only accept windows
    /// drawn where AX says they are (both in top-left-origin coordinates).
    func isVisible(_ id: CGWindowID, axFrame: CGRect) -> Bool {
        guard let drawn = bounds[id] else { return false }
        return abs(drawn.width - axFrame.width) < 8 && abs(drawn.height - axFrame.height) < 8
            && abs(drawn.minX - axFrame.minX) < 8 && abs(drawn.minY - axFrame.minY) < 8
    }
}
