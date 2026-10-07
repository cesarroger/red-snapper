import AppKit
import SnapCore

/// Watches global mouse events; when the user drags a window's title bar to a screen
/// edge or corner it shows a preview, and on release snaps the window into that zone.
/// Dragging a window that RED SNAPPER snapped restores its pre-snap size.
///
/// Uses `NSEvent` global monitors (observe-only; they never block or alter events), which
/// receive other apps' mouse events once the process is trusted for Accessibility.
/// Identifying the dragged window needs Accessibility calls that can block on a hung app,
/// so that happens on `detectionQueue`; the main thread only handles UI.
final class DragSnapController {
    private let windowManager: WindowManager
    private let settings: AppSettings
    private let overlay = SnapPreviewOverlay()
    private let detector = DragZoneDetector(edgeThreshold: 6, cornerSize: 60)
    private let detectionQueue = DispatchQueue(label: "com.csr.RedSnapper.drag", qos: .userInteractive)
    private var monitors: [Any] = []

    private enum State {
        case idle
        /// Mouse is down; we haven't looked at what's under it yet (plain clicks cost nothing).
        case pressed
        /// Background detection is figuring out whether a window is being moved.
        case detecting
        /// The window is being moved by its title bar.
        /// `origin` is the frame to restore to later: where the window was before the drag
        /// (or its restored size, if it was a snapped window dragged off its zone). AX coordinates.
        case moving(window: AXWindow, origin: CGRect, context: SnapContext, zone: SnapZone?, screen: ScreenInfo?)
    }
    private var state: State = .idle
    /// Incremented on every mouse-down so stale background results are ignored.
    private var session = 0

    init(windowManager: WindowManager, settings: AppSettings) {
        self.windowManager = windowManager
        self.settings = settings
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(m) }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        overlay.hide()
        state = .idle
    }

    // MARK: - Event handling (main thread)

    private func mouseDown() {
        session += 1
        state = .pressed
    }

    private func mouseDragged() {
        switch state {
        case .pressed:
            state = .detecting
            let ctx = SnapContext.capture(settings)
            detect(session: session, cursorAX: ctx.converter.toAX(NSEvent.mouseLocation), ctx: ctx)
        case .moving:
            updatePreview()
        case .idle, .detecting:
            return
        }
    }

    private func mouseUp() {
        defer { state = .idle }
        guard case let .moving(window, origin, _, zone, screen) = state else { return }
        overlay.hide()
        guard let zone, let screen else { return }
        // Let the window server finish the drag before we reposition the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.windowManager.snap(window, to: zone, onScreenWithID: screen.id, originalFrame: origin) { snapped in
                guard let self, let snapped else { return }
                self.reassert(snapped, for: window, zone: zone, screenID: screen.id, attemptsLeft: 3)
            }
        }
    }

    private func beganMoving(_ window: AXWindow, startFrame: CGRect, ctx: SnapContext, session: Int) {
        guard session == self.session, case .detecting = state else { return }
        state = .moving(window: window, origin: startFrame, context: ctx, zone: nil, screen: nil)
        let cursorAX = ctx.converter.toAX(NSEvent.mouseLocation)
        windowManager.restoreSizeForDrag(window, startFrame: startFrame, cursorAX: cursorAX) { [weak self] restored in
            guard let self, let restored, session == self.session,
                  case let .moving(w, _, c, z, sc) = self.state, w == window else { return }
            self.state = .moving(window: w, origin: restored, context: c, zone: z, screen: sc)
        }
        updatePreview()
    }

    private func updatePreview() {
        guard case let .moving(window, origin, ctx, oldZone, oldScreen) = state else { return }
        let point = NSEvent.mouseLocation
        let screen = ctx.screen(containing: point)
        let zone = screen.flatMap { detector.zone(for: point, screenFrame: $0.frame) }
        guard zone != oldZone || screen != oldScreen else { return }
        state = .moving(window: window, origin: origin, context: ctx, zone: zone, screen: screen)

        if let zone, let screen {
            overlay.show(LayoutEngine.frame(for: zone, in: screen.visibleFrame, gap: ctx.gap))
        } else {
            overlay.hide()
        }
    }

    // MARK: - Background detection

    /// Finds the window under the cursor and watches whether it moves (title-bar drag),
    /// resizes (edge drag), or stays put (e.g. text selection), without touching the main thread.
    private func detect(session: Int, cursorAX: CGPoint, ctx: SnapContext) {
        detectionQueue.async { [weak self] in
            let ownPID = ProcessInfo.processInfo.processIdentifier
            guard let window = AXWindow.hitTest(axPoint: cursorAX)?.window,
                  window.pid != ownPID, !ctx.isExcluded(pid: window.pid),
                  window.isStandardWindow, window.isMovable, !window.isFullScreen,
                  let start = window.frame
            else { return }

            for _ in 0..<40 {
                usleep(20_000)
                guard NSEvent.pressedMouseButtons & 1 != 0, let frame = window.frame else { return }
                let resized = abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1
                let moved = abs(frame.minX - start.minX) > 1 || abs(frame.minY - start.minY) > 1
                if resized { return }
                if moved {
                    DispatchQueue.main.async { self?.beganMoving(window, startFrame: start, ctx: ctx, session: session) }
                    return
                }
            }
        }
    }

    /// macOS's own "drag to screen edge to tile" (on by default since macOS 15) also reacts to
    /// the release and animates the window into *its* tile after ours. Watch briefly and
    /// re-apply our zone if something else moved the window, unless the user grabbed it again.
    private func reassert(_ expected: CGRect, for window: AXWindow, zone: SnapZone, screenID: String, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        let session = self.session
        detectionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard NSEvent.pressedMouseButtons & 1 == 0, let current = window.frame else { return }
            let drifted = !DragRestore.isUnchanged(current, since: expected, tolerance: 0.5)
            DispatchQueue.main.async {
                guard let self, session == self.session, case .idle = self.state else { return }
                if drifted {
                    self.windowManager.snap(window, to: zone, onScreenWithID: screenID, reasserting: true) { result in
                        self.reassert(result ?? expected, for: window, zone: zone, screenID: screenID,
                                      attemptsLeft: attemptsLeft - 1)
                    }
                } else {
                    self.reassert(expected, for: window, zone: zone, screenID: screenID, attemptsLeft: attemptsLeft - 1)
                }
            }
        }
    }
}
