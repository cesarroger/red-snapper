import CoreGraphics

public enum HorizontalDirection: Sendable, Equatable {
    case left, right
}

/// What pressing a zone shortcut should do, given where the window already is.
///
/// * Pressing a half/third again cycles its size: ½ → ⅔ → ⅓ → ½ (and ⅓ → ⅔ → ⅓).
/// * At the end of a left/right cycle, if there is a display on that side, the window
///   hops to it and lands on the facing half (left half → neighbour's right half).
public enum SnapCycle {
    public enum Decision: Equatable, Sendable {
        case snap(SnapZone)
        case hop(HorizontalDirection, SnapZone)
    }

    /// The sizes visited by repeatedly pressing `zone`'s shortcut, starting with `zone`.
    public static func sequence(for zone: SnapZone) -> [SnapZone] {
        switch zone {
        case .leftHalf: return [.leftHalf, .leftTwoThirds, .leftThird]
        case .rightHalf: return [.rightHalf, .rightTwoThirds, .rightThird]
        case .topHalf: return [.topHalf, .topTwoThirds, .topThird]
        case .bottomHalf: return [.bottomHalf, .bottomTwoThirds, .bottomThird]
        case .leftThird: return [.leftThird, .leftTwoThirds]
        case .rightThird: return [.rightThird, .rightTwoThirds]
        default: return [zone]
        }
    }

    /// The direction a zone can hop to an adjacent display, and the zone it lands in there.
    public static func hop(for zone: SnapZone) -> (HorizontalDirection, SnapZone)? {
        switch zone {
        case .leftHalf: return (.left, .rightHalf)
        case .rightHalf: return (.right, .leftHalf)
        default: return nil
        }
    }

    /// - Parameters:
    ///   - currentFrame / visibleFrame: AppKit coordinates on the window's current display.
    ///   - hasDisplay: whether a display exists on the given side of the current one.
    public static func decide(pressed zone: SnapZone,
                              currentFrame: CGRect,
                              visibleFrame: CGRect,
                              gap: CGFloat,
                              cycleSizes: Bool,
                              hopDisplays: Bool,
                              hasDisplay: (HorizontalDirection) -> Bool) -> Decision {
        let steps = cycleSizes ? sequence(for: zone) : [zone]
        guard let index = steps.firstIndex(where: {
            LayoutEngine.frame(currentFrame, matches: $0, in: visibleFrame, gap: gap)
        }) else {
            return .snap(zone)
        }
        if index < steps.count - 1 { return .snap(steps[index + 1]) }

        // End of the cycle (or already in place with cycling off).
        if hopDisplays, let (direction, landing) = hop(for: zone), hasDisplay(direction) {
            return .hop(direction, landing)
        }
        return .snap(steps[0])
    }
}
