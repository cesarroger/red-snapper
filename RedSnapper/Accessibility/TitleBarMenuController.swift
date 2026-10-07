import AppKit
import SnapCore

/// Right-clicking an empty part of a window's title bar opens RED SNAPPER's snap picker.
///
/// Needs to *swallow* that right-click (so the app doesn't also react), which requires an
/// active `CGEvent` tap rather than an observe-only monitor. The decision must be made
/// synchronously inside the tap, so it is kept cheap and bounded:
/// 1. a window-server lookup (never blocks) checks the click is in the top band of a window;
/// 2. only then a Accessibility hit-test with a 50 ms cap confirms it hit bare window chrome
///    (role `AXWindow`), not a toolbar button, tab, or the window's content.
final class TitleBarMenuController {
    private let settings: AppSettings
    private let onRequest: (AXWindow, NSPoint) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowNextRightMouseUp = false

    /// Height of the band at the top of a window treated as title bar.
    private let titleBandHeight: CGFloat = 30

    init(settings: AppSettings, onRequest: @escaping (AXWindow, NSPoint) -> Void) {
        self.settings = settings
        self.onRequest = onRequest
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, refcon in
                                              guard let refcon else { return Unmanaged.passUnretained(event) }
                                              let me = Unmanaged<TitleBarMenuController>.fromOpaque(refcon).takeUnretainedValue()
                                              return me.handle(type: type, event: event)
                                          },
                                          userInfo: refcon)
        else {
            NSLog("RED SNAPPER: could not create title-bar event tap (Accessibility not granted?)")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .rightMouseUp:
            if swallowNextRightMouseUp {
                swallowNextRightMouseUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .rightMouseDown:
            // Plain right-click only; modified clicks keep their usual meaning.
            let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty,
                  let window = titleBarWindow(at: event.location) else { return Unmanaged.passUnretained(event) }
            swallowNextRightMouseUp = true
            let appKitPoint = NSEvent.mouseLocation
            DispatchQueue.main.async { self.onRequest(window, appKitPoint) }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// `point` is in AX/Quartz coordinates (top-left origin), like `CGEvent.location`.
    private func titleBarWindow(at point: CGPoint) -> AXWindow? {
        // 1. Cheap: the front-most normal window under the cursor, from the window server.
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let hit = list.first(where: { info in
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.contains(point)
        }),
              (hit[kCGWindowLayer as String] as? Int) == 0,
              let pid = hit[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
              let dict = hit[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              point.y - bounds.minY <= titleBandHeight
        else { return nil }

        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           settings.isExcluded(bundleID) { return nil }

        // 2. Confirm it's bare chrome, not a control in a unified toolbar. Bounded to 50 ms.
        guard let (window, role) = AXWindow.hitTest(axPoint: point, timeout: 0.05),
              role == kAXWindowRole, window.pid == pid, window.isStandardWindow, !window.isFullScreen
        else { return nil }
        return window
    }
}
