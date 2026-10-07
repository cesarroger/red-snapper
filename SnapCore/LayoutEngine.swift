import CoreGraphics

/// Pure layout math. All rectangles are in **AppKit coordinates**
/// (origin at the bottom-left of the primary display, y grows upward),
/// i.e. the same space as `NSScreen.frame` / `NSScreen.visibleFrame`.
public enum LayoutEngine {

    /// The frame a window should occupy for `zone` on a screen whose visible frame is `visibleFrame`.
    ///
    /// - Parameters:
    ///   - gap: points of empty space between windows and between windows and the screen edges.
    ///   - windowSize: the window's current size; only used by `.center`.
    public static func frame(for zone: SnapZone,
                             in visibleFrame: CGRect,
                             gap: CGFloat,
                             windowSize: CGSize? = nil) -> CGRect {
        let gap = max(0, gap)
        let usable = visibleFrame.insetBy(dx: gap, dy: gap)

        guard let span = zone.gridSpan else {
            return centered(size: windowSize ?? defaultCenterSize(in: usable), in: usable)
        }

        let cellWidth = (usable.width - gap * CGFloat(span.columns - 1)) / CGFloat(span.columns)
        let cellHeight = (usable.height - gap * CGFloat(span.rows - 1)) / CGFloat(span.rows)

        let width = cellWidth * CGFloat(span.columnSpan) + gap * CGFloat(span.columnSpan - 1)
        let height = cellHeight * CGFloat(span.rowSpan) + gap * CGFloat(span.rowSpan - 1)

        let x = usable.minX + CGFloat(span.column) * (cellWidth + gap)
        // Row 0 is the top row, but AppKit's y axis points up.
        let topOffset = CGFloat(span.row) * (cellHeight + gap)
        let y = usable.maxY - topOffset - height

        return rounded(CGRect(x: x, y: y, width: width, height: height))
    }

    /// Re-positions a window whose actual size differs from the requested `target`
    /// (e.g. because it has a minimum size) so that it stays anchored to the
    /// zone's outer edges and inside `visibleFrame`.
    public static func adjust(target: CGRect,
                              actualSize: CGSize,
                              in visibleFrame: CGRect,
                              gap: CGFloat) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: max(0, gap), dy: max(0, gap))
        let tolerance: CGFloat = 1

        func anchoredOrigin(targetMin: CGFloat, targetMax: CGFloat, boundsMin: CGFloat, boundsMax: CGFloat, length: CGFloat) -> CGFloat {
            let touchesMin = abs(targetMin - boundsMin) <= tolerance
            let touchesMax = abs(targetMax - boundsMax) <= tolerance
            var origin: CGFloat
            if touchesMax && !touchesMin {
                origin = targetMax - length              // keep the far edge pinned
            } else if touchesMin && !touchesMax {
                origin = targetMin                       // keep the near edge pinned
            } else {
                origin = (targetMin + targetMax) / 2 - length / 2  // center on the zone
            }
            // Keep on-screen; if larger than the screen, pin to the min edge.
            origin = min(origin, boundsMax - length)
            origin = max(origin, boundsMin)
            return origin
        }

        let x = anchoredOrigin(targetMin: target.minX, targetMax: target.maxX,
                               boundsMin: bounds.minX, boundsMax: bounds.maxX, length: actualSize.width)
        // For y we want "top" anchoring to win when the window is too tall,
        // so pin to maxY (the top in AppKit space) when it doesn't fit.
        var y = anchoredOrigin(targetMin: target.minY, targetMax: target.maxY,
                               boundsMin: bounds.minY, boundsMax: bounds.maxY, length: actualSize.height)
        if actualSize.height > bounds.height { y = bounds.maxY - actualSize.height }

        return rounded(CGRect(origin: CGPoint(x: x, y: y), size: actualSize))
    }

    /// Whether `frame` already matches `zone` on this screen (within `tolerance` points).
    public static func frame(_ frame: CGRect, matches zone: SnapZone, in visibleFrame: CGRect, gap: CGFloat, tolerance: CGFloat = 4) -> Bool {
        guard zone != .center else { return false }
        let expected = self.frame(for: zone, in: visibleFrame, gap: gap)
        return abs(frame.minX - expected.minX) <= tolerance
            && abs(frame.minY - expected.minY) <= tolerance
            && abs(frame.width - expected.width) <= tolerance
            && abs(frame.height - expected.height) <= tolerance
    }

    // MARK: - Helpers

    static func centered(size: CGSize, in bounds: CGRect) -> CGRect {
        let w = min(size.width, bounds.width)
        let h = min(size.height, bounds.height)
        return rounded(CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h))
    }

    static func defaultCenterSize(in bounds: CGRect) -> CGSize {
        CGSize(width: bounds.width * 2 / 3, height: bounds.height * 2 / 3)
    }

    /// Rounds each *edge* to whole points (rather than origin and size separately)
    /// so adjacent zones share an edge exactly and never overflow the screen.
    static func rounded(_ r: CGRect) -> CGRect {
        let minX = r.minX.rounded(), maxX = r.maxX.rounded()
        let minY = r.minY.rounded(), maxY = r.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
