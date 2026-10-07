import Foundation

/// Pure decisions for the "4-up grid" action: which windows, and which zone each gets.
public enum GridPlanner {
    public struct Candidate: Equatable, Sendable {
        public var id: UInt32
        /// Position in the most-recently-used list (0 = most recent), nil if never tracked.
        public var recency: Int?
        /// Front-to-back stacking position on screen (0 = frontmost).
        public var zOrder: Int

        public init(id: UInt32, recency: Int?, zOrder: Int) {
            self.id = id
            self.recency = recency
            self.zOrder = zOrder
        }
    }

    /// Picks up to `limit` windows: tracked windows by recency first, then untracked
    /// ones by stacking order (front-most windows were used more recently).
    public static func pick(_ candidates: [Candidate], limit: Int = 4) -> [UInt32] {
        candidates
            .sorted { ($0.recency ?? .max, $0.zOrder) < ($1.recency ?? .max, $1.zOrder) }
            .prefix(limit)
            .map(\.id)
    }

    /// Zones for `count` windows, most recent first. Fewer than four windows still
    /// fill the screen: 1 → maximize, 2 → halves, 3 → left half + right quarters.
    public static func zones(forWindowCount count: Int) -> [SnapZone] {
        switch count {
        case ..<1: return []
        case 1: return [.maximize]
        case 2: return [.leftHalf, .rightHalf]
        case 3: return [.leftHalf, .topRight, .bottomRight]
        default: return SnapZone.fourUpOrder
        }
    }
}
