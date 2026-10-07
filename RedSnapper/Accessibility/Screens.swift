import AppKit
import SnapCore

/// A display, captured as plain values so it can be used off the main thread.
struct ScreenInfo: Equatable {
    /// Stable identifier (the display's UUID) that survives reboots and re-plugging.
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect

    init(_ screen: NSScreen) {
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        id = Self.uuid(for: screen) ?? "\(screen.localizedName)-\(Int(screen.frame.minX))x\(Int(screen.frame.minY))"
    }

    private static func uuid(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Everything a window operation needs to know, captured on the main thread (where
/// `NSScreen` and the settings live) and then handed to the background AX queue.
struct SnapContext {
    /// `screens[0]` is the primary display (the one whose frame origin is 0,0).
    let screens: [ScreenInfo]
    let converter: CoordinateConverter
    let gap: CGFloat
    let excludedBundleIDs: Set<String>
    let cycleSizes: Bool
    let hopDisplays: Bool

    /// Must be called on the main thread.
    static func capture(_ settings: AppSettings) -> SnapContext {
        dispatchPrecondition(condition: .onQueue(.main))
        let screens = NSScreen.screens.map(ScreenInfo.init)
        return SnapContext(screens: screens,
                           converter: CoordinateConverter(primaryScreenHeight: screens.first?.frame.height ?? 0),
                           gap: CGFloat(settings.gap),
                           excludedBundleIDs: Set(settings.excludedBundleIDs),
                           cycleSizes: settings.cycleSizes,
                           hopDisplays: settings.hopDisplays)
    }

    private var frames: [CGRect] { screens.map(\.frame) }

    /// The screen a window (AppKit frame) is on.
    func screen(for appKitFrame: CGRect) -> ScreenInfo? {
        ScreenMath.screenIndex(for: appKitFrame, screenFrames: frames).map { screens[$0] }
    }

    func screen(containing appKitPoint: CGPoint) -> ScreenInfo? {
        ScreenMath.screenIndex(containing: appKitPoint, screenFrames: frames).map { screens[$0] }
    }

    func screen(withID id: String) -> ScreenInfo? {
        screens.first { $0.id == id }
    }

    /// Next/previous display in spatial order, wrapping around.
    func adjacent(to screen: ScreenInfo, forward: Bool) -> ScreenInfo? {
        guard let i = screens.firstIndex(of: screen),
              let j = ScreenMath.adjacentScreenIndex(from: i, screenFrames: frames, forward: forward) else { return nil }
        return screens[j]
    }

    /// The display physically to the left/right (no wrapping).
    func neighbor(of screen: ScreenInfo, _ direction: HorizontalDirection) -> ScreenInfo? {
        guard let i = screens.firstIndex(of: screen),
              let j = ScreenMath.neighborIndex(of: i, direction: direction, screenFrames: frames) else { return nil }
        return screens[j]
    }

    func isExcluded(pid: pid_t) -> Bool {
        guard !excludedBundleIDs.isEmpty,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return excludedBundleIDs.contains(bundleID)
    }
}
