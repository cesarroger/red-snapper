import CoreGraphics

/// When a snapped window is dragged away, it goes back to its pre-snap size while the
/// title bar stays under the cursor at the same relative position.
public enum DragRestore {
    /// - Parameters (all in AX / top-left coordinates):
    ///   - frame: the window's current (snapped) frame.
    ///   - originalSize: the size it had before it was snapped.
    ///   - cursor: the mouse location.
    public static func frame(from frame: CGRect, originalSize: CGSize, cursor: CGPoint) -> CGRect {
        guard frame.width > 0 else { return CGRect(origin: frame.origin, size: originalSize) }
        let fraction = min(max((cursor.x - frame.minX) / frame.width, 0), 1)
        let x = cursor.x - fraction * originalSize.width
        return CGRect(x: x.rounded(), y: frame.minY, width: originalSize.width, height: originalSize.height)
    }

    /// Whether `current` is still where we snapped it (so it hasn't been moved or resized since).
    public static func isUnchanged(_ current: CGRect, since snapped: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(current.minX - snapped.minX) <= tolerance && abs(current.minY - snapped.minY) <= tolerance
            && abs(current.width - snapped.width) <= tolerance && abs(current.height - snapped.height) <= tolerance
    }
}
