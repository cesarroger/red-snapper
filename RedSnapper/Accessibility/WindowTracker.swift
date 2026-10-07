import AppKit
import ApplicationServices

/// Keeps a most-recently-used list of windows (by `CGWindowID`) by listening for app
/// activations and, per app, Accessibility "focused window changed" notifications.
final class WindowTracker {
    /// Written on the main thread (notifications), read from the AX queue, so guarded by a lock.
    private var recentWindowIDs: [CGWindowID] = []
    private let lock = NSLock()
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private let maxTracked = 64

    func start() {
        guard workspaceTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.observe(app)
                self?.recordFocusedWindow(of: app.processIdentifier)
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.stopObserving(app.processIdentifier)
            },
        ]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            recordFocusedWindow(of: front.processIdentifier)
        }
    }

    /// Rank of a window in the MRU list (0 = most recent), or nil if never seen focused.
    func recency(of id: CGWindowID) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return recentWindowIDs.firstIndex(of: id)
    }

    func record(_ window: AXWindow) {
        guard window.isStandardWindow, let id = window.windowID else { return }
        lock.lock(); defer { lock.unlock() }
        recentWindowIDs.removeAll { $0 == id }
        recentWindowIDs.insert(id, at: 0)
        if recentWindowIDs.count > maxTracked { recentWindowIDs.removeLast() }
    }

    // MARK: - Private

    private func recordFocusedWindow(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.messagingTimeout)
        if let window: AXUIElement = app.attribute(kAXFocusedWindowAttribute) {
            record(AXWindow(element: window))
        }
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.record(AXWindow(element: element))
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
