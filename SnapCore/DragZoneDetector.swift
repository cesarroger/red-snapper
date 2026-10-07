import CoreGraphics

/// Decides which snap zone (if any) a dragged window should preview, based on
/// where the cursor is relative to the edges of the screen it is on.
///
/// * corners → quarters
/// * left / right edge → halves
/// * top edge → maximize
/// * bottom edge → thirds (left / center / right depending on x)
public struct DragZoneDetector: Sendable {
    /// How close (pt) the cursor must be to an edge to trigger it.
    public var edgeThreshold: CGFloat
    /// How far (pt) from a corner along each edge still counts as that corner.
    public var cornerSize: CGFloat

    public init(edgeThreshold: CGFloat = 6, cornerSize: CGFloat = 60) {
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
    }

    /// - Parameters:
    ///   - point: cursor location in AppKit coordinates.
    ///   - screenFrame: the *full* frame (`NSScreen.frame`) of the screen under the cursor.
    public func zone(for point: CGPoint, screenFrame f: CGRect) -> SnapZone? {
        let nearLeft = point.x <= f.minX + edgeThreshold
        let nearRight = point.x >= f.maxX - edgeThreshold
        let nearTop = point.y >= f.maxY - edgeThreshold
        let nearBottom = point.y <= f.minY + edgeThreshold

        let inLeftCornerBand = point.x <= f.minX + cornerSize
        let inRightCornerBand = point.x >= f.maxX - cornerSize
        let inTopCornerBand = point.y >= f.maxY - cornerSize
        let inBottomCornerBand = point.y <= f.minY + cornerSize

        // Corners: touching one edge while within the corner band of the perpendicular edge.
        if (nearLeft && inTopCornerBand) || (nearTop && inLeftCornerBand) { return .topLeft }
        if (nearRight && inTopCornerBand) || (nearTop && inRightCornerBand) { return .topRight }
        if (nearLeft && inBottomCornerBand) || (nearBottom && inLeftCornerBand) { return .bottomLeft }
        if (nearRight && inBottomCornerBand) || (nearBottom && inRightCornerBand) { return .bottomRight }

        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearTop { return .maximize }
        if nearBottom {
            let third = f.width / 3
            switch point.x - f.minX {
            case ..<third: return .leftThird
            case ..<(third * 2): return .centerThird
            default: return .rightThird
            }
        }
        return nil
    }
}
