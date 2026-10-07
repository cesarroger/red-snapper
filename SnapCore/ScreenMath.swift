import CoreGraphics

/// Pure helpers for choosing and moving between displays. All rects in AppKit coordinates.
public enum ScreenMath {

    /// Index of the screen a window "is on": the one with the largest overlap,
    /// falling back to the screen whose center is nearest the window's center.
    public static func screenIndex(for windowFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (i, screen) in screenFrames.enumerated() {
            let overlap = screen.intersection(windowFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (i, area) }
        }
        if let best { return best.index }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screenFrames.indices.min { a, b in
            distanceSquared(center, screenFrames[a]) < distanceSquared(center, screenFrames[b])
        }
    }

    /// Index of the screen containing `point`, if any.
    public static func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        // Use a half-open test widened by 1pt on the max edges so the very top/right pixel counts.
        screenFrames.firstIndex { f in
            point.x >= f.minX && point.x <= f.maxX && point.y >= f.minY && point.y <= f.maxY
        }
    }

    /// Screen indices ordered spatially (left-to-right, then top-to-bottom) for next/previous cycling.
    public static func spatialOrder(of screenFrames: [CGRect]) -> [Int] {
        screenFrames.indices.sorted { a, b in
            let fa = screenFrames[a], fb = screenFrames[b]
            if fa.minX != fb.minX { return fa.minX < fb.minX }
            return fa.maxY > fb.maxY
        }
    }

    /// The neighbouring screen index in spatial order, wrapping around.
    public static func adjacentScreenIndex(from index: Int, screenFrames: [CGRect], forward: Bool) -> Int? {
        let order = spatialOrder(of: screenFrames)
        guard order.count > 1, let pos = order.firstIndex(of: index) else { return nil }
        let next = (pos + (forward ? 1 : -1) + order.count) % order.count
        return order[next]
    }

    /// The display directly to the left/right of `index` (no wrapping): among screens lying
    /// entirely on that side, prefer the most vertical overlap, then the nearest one.
    public static func neighborIndex(of index: Int, direction: HorizontalDirection, screenFrames: [CGRect]) -> Int? {
        guard screenFrames.indices.contains(index) else { return nil }
        let origin = screenFrames[index]
        let candidates = screenFrames.indices.filter { i in
            guard i != index else { return false }
            let f = screenFrames[i]
            return direction == .left ? f.maxX <= origin.minX + 1 : f.minX >= origin.maxX - 1
        }
        func overlap(_ i: Int) -> CGFloat {
            let f = screenFrames[i]
            return max(0, min(f.maxY, origin.maxY) - max(f.minY, origin.minY))
        }
        func distance(_ i: Int) -> CGFloat {
            let f = screenFrames[i]
            return direction == .left ? origin.minX - f.maxX : f.minX - origin.maxX
        }
        return candidates.min { a, b in
            let oa = overlap(a), ob = overlap(b)
            if (oa > 0) != (ob > 0) { return oa > 0 }
            if distance(a) != distance(b) { return distance(a) < distance(b) }
            return oa > ob
        }
    }

    /// Maps a window frame from one screen's visible frame to another's, preserving its
    /// position and size *relative* to the screen (e.g. a window covering the right
    /// 40% stays on the right 40%). The result is clamped inside the destination.
    public static func relocate(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let rx = (frame.minX - source.minX) / source.width
        let ry = (frame.minY - source.minY) / source.height
        let rw = frame.width / source.width
        let rh = frame.height / source.height

        var w = min(rw * destination.width, destination.width)
        var h = min(rh * destination.height, destination.height)
        w = w.rounded(); h = h.rounded()
        var x = destination.minX + rx * destination.width
        var y = destination.minY + ry * destination.height
        x = min(max(x, destination.minX), destination.maxX - w)
        y = min(max(y, destination.minY), destination.maxY - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
    }

    private static func distanceSquared(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = p.x - r.midX, dy = p.y - r.midY
        return dx * dx + dy * dy
    }
}
