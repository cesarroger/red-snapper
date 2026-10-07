import Foundation

/// A region of a screen that a window can be snapped into.
///
/// Every zone is described as a span of cells in a `columns` x `rows` grid laid
/// over a screen's visible frame. Row 0 is the *top* row.
public enum SnapZone: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case topThird, topTwoThirds, bottomThird, bottomTwoThirds
    case maximize
    case center

    public struct GridSpan: Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        public var column: Int
        public var row: Int
        public var columnSpan: Int = 1
        public var rowSpan: Int = 1
    }

    /// Grid description for grid-based zones; `nil` for `.center`, which keeps the window's size.
    public var gridSpan: GridSpan? {
        switch self {
        case .leftHalf:    return GridSpan(columns: 2, rows: 1, column: 0, row: 0)
        case .rightHalf:   return GridSpan(columns: 2, rows: 1, column: 1, row: 0)
        case .topHalf:     return GridSpan(columns: 1, rows: 2, column: 0, row: 0)
        case .bottomHalf:  return GridSpan(columns: 1, rows: 2, column: 0, row: 1)
        case .topLeft:     return GridSpan(columns: 2, rows: 2, column: 0, row: 0)
        case .topRight:    return GridSpan(columns: 2, rows: 2, column: 1, row: 0)
        case .bottomLeft:  return GridSpan(columns: 2, rows: 2, column: 0, row: 1)
        case .bottomRight: return GridSpan(columns: 2, rows: 2, column: 1, row: 1)
        case .leftThird:   return GridSpan(columns: 3, rows: 1, column: 0, row: 0)
        case .centerThird: return GridSpan(columns: 3, rows: 1, column: 1, row: 0)
        case .rightThird:  return GridSpan(columns: 3, rows: 1, column: 2, row: 0)
        case .leftTwoThirds:   return GridSpan(columns: 3, rows: 1, column: 0, row: 0, columnSpan: 2)
        case .rightTwoThirds:  return GridSpan(columns: 3, rows: 1, column: 1, row: 0, columnSpan: 2)
        case .topThird:        return GridSpan(columns: 1, rows: 3, column: 0, row: 0)
        case .topTwoThirds:    return GridSpan(columns: 1, rows: 3, column: 0, row: 0, rowSpan: 2)
        case .bottomThird:     return GridSpan(columns: 1, rows: 3, column: 0, row: 2)
        case .bottomTwoThirds: return GridSpan(columns: 1, rows: 3, column: 0, row: 1, rowSpan: 2)
        case .maximize:    return GridSpan(columns: 1, rows: 1, column: 0, row: 0)
        case .center:      return nil
        }
    }

    public var displayName: String { Self.words(rawValue) }

    /// "leftTwoThirds" → "Left Two Thirds".
    static func words(_ camelCase: String) -> String {
        camelCase.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    /// The four cells of the 2x2 "4-up" grid, in fill order (most recent window first).
    public static let fourUpOrder: [SnapZone] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
