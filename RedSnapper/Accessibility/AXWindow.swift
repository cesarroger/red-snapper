import AppKit
import ApplicationServices

/// Private but long-stable API (used by most window managers) to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin wrapper around an `AXUIElement` window. Frames are exposed in **AX coordinates**
/// (top-left origin); callers convert with `CoordinateConverter`.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    /// AX calls to a hung app block until the messaging timeout; keep it short.
    static let messagingTimeout: Float = 0.3

    init(element: AXUIElement) {
        self.element = element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        self.pid = pid
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    // MARK: - Lookup

    /// The focused (or main) window of the given application.
    static func focused(pid: pid_t) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        if let window: AXUIElement = appElement.attribute(kAXFocusedWindowAttribute) {
            return AXWindow(element: window)
        }
        if let window: AXUIElement = appElement.attribute(kAXMainWindowAttribute) {
            return AXWindow(element: window)
        }
        return nil
    }

    /// The window under a point plus the role of the exact element that was hit
    /// (`AXWindow` itself means bare window chrome, e.g. an empty title bar).
    static func hitTest(axPoint: CGPoint, timeout: Float = messagingTimeout) -> (window: AXWindow, hitRole: String?)? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &hit) == .success,
              let element = hit else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        let role = element.role

        if role == kAXWindowRole { return (AXWindow(element: element), role) }
        if let window: AXUIElement = element.attribute(kAXWindowAttribute) { return (AXWindow(element: window), role) }

        // Walk up the parent chain as a fallback.
        var current: AXUIElement? = element
        for _ in 0..<20 {
            guard let c = current else { break }
            if c.role == kAXWindowRole { return (AXWindow(element: c), role) }
            current = c.attribute(kAXParentAttribute)
        }
        return nil
    }

    /// All standard windows of an application.
    static func windows(of pid: pid_t) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        let windows: [AXUIElement] = appElement.attribute(kAXWindowsAttribute) ?? []
        return windows.map(AXWindow.init(element:))
    }

    // MARK: - Attributes

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    var position: CGPoint? {
        guard let value: AXValue = element.attribute(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value: AXValue = element.attribute(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Frame in AX coordinates.
    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    var isMinimized: Bool { element.attribute(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { element.attribute("AXFullScreen") ?? false }
    var subrole: String? { element.attribute(kAXSubroleAttribute) }
    var title: String? { element.attribute(kAXTitleAttribute) }

    /// A normal, user-arrangeable window (not a sheet, panel, popover, etc.).
    var isStandardWindow: Bool { subrole == kAXStandardWindowSubrole }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success && settable.boolValue
    }

    var isMovable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success && settable.boolValue
    }

    // MARK: - Mutation

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    /// Sets the frame (AX coordinates) and returns the frame the window actually ended up with.
    ///
    /// Size is applied before *and* after moving: shrinking first lets the window fit on a
    /// smaller destination display, and the second pass fixes apps that clamp size to the
    /// display they were on when the first size was applied.
    @discardableResult
    func setFrame(_ frame: CGRect) -> CGRect? {
        withEnhancedUserInterfaceDisabled {
            setSize(frame.size)
            setPosition(frame.origin)
            setSize(frame.size)
        }
        return self.frame
    }

    func setMinimized(_ minimized: Bool) {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString,
                                     (minimized ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Apps with `AXEnhancedUserInterface` on (often enabled by VoiceOver or other
    /// assistive tools) animate frame changes and can ignore some of them.
    private func withEnhancedUserInterfaceDisabled(_ body: () -> Void) {
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        let wasEnabled: Bool = app.attribute("AXEnhancedUserInterface") ?? false
        if wasEnabled { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        body()
        if wasEnabled { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) }
    }
}

extension AXWindow: Equatable {
    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool { CFEqual(lhs.element, rhs.element) }
}

// MARK: - AXUIElement attribute helper

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success, let value else { return nil }
        // CF types (AXUIElement, AXValue) can't be conditionally cast with `as?` reliably across
        // all toolchains, so check the CFTypeID for those explicitly.
        if T.self == AXUIElement.self {
            return CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! T) : nil
        }
        if T.self == AXValue.self {
            return CFGetTypeID(value) == AXValueGetTypeID() ? (value as! T) : nil
        }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }
}
