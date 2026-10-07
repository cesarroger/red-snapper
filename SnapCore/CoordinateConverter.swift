import CoreGraphics

/// Converts between the two global coordinate spaces macOS uses:
///
/// * **AppKit** (`NSScreen`, `NSWindow`, `NSEvent.mouseLocation`): origin at the
///   bottom-left of the *primary* display (the one with the menu bar at index 0
///   of `NSScreen.screens`), y grows **up**.
/// * **Accessibility / Quartz** (`kAXPositionAttribute`, `CGWindowList`, `CGEvent`):
///   origin at the top-left of the primary display, y grows **down**.
///
/// The x axis is identical, so only y needs flipping, about the primary display's height.
public struct CoordinateConverter: Sendable {
    public let primaryScreenHeight: CGFloat

    public init(primaryScreenHeight: CGFloat) {
        self.primaryScreenHeight = primaryScreenHeight
    }

    /// AppKit rect -> AX rect (AX `position` is the window's top-left corner).
    public func toAX(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// AX rect -> AppKit rect. The flip is its own inverse.
    public func toAppKit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func toAX(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    public func toAppKit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
