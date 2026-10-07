import XCTest
@testable import SnapCore

final class GridPlannerTests: XCTestCase {
    func testRecentWindowsComeFirstInRecencyOrder() {
        let picked = GridPlanner.pick([
            .init(id: 1, recency: 2, zOrder: 0),
            .init(id: 2, recency: 0, zOrder: 3),
            .init(id: 3, recency: nil, zOrder: 1),
            .init(id: 4, recency: 1, zOrder: 2),
        ])
        XCTAssertEqual(picked, [2, 4, 1, 3])
    }

    func testUntrackedWindowsFallBackToStackingOrder() {
        let picked = GridPlanner.pick([
            .init(id: 10, recency: nil, zOrder: 4),
            .init(id: 11, recency: nil, zOrder: 1),
            .init(id: 12, recency: 0, zOrder: 9),
            .init(id: 13, recency: nil, zOrder: 0),
            .init(id: 14, recency: nil, zOrder: 2),
        ])
        XCTAssertEqual(picked, [12, 13, 11, 14])
    }

    func testLimit() {
        let many = (0..<10).map { GridPlanner.Candidate(id: UInt32($0), recency: $0, zOrder: 0) }
        XCTAssertEqual(GridPlanner.pick(many).count, 4)
        XCTAssertEqual(GridPlanner.pick(many, limit: 2), [0, 1])
    }

    func testZonesForCounts() {
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 0), [])
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 1), [.maximize])
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 2), [.leftHalf, .rightHalf])
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 3), [.leftHalf, .topRight, .bottomRight])
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 4), [.topLeft, .topRight, .bottomLeft, .bottomRight])
        XCTAssertEqual(GridPlanner.zones(forWindowCount: 9).count, 4)
    }

    func testFourUpZonesTileWithoutOverlapWithGap() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 804)
        let frames = GridPlanner.zones(forWindowCount: 4).map { LayoutEngine.frame(for: $0, in: visible, gap: 10) }
        for i in frames.indices {
            XCTAssertTrue(visible.contains(frames[i]))
            for j in frames.indices where j > i { XCTAssertFalse(frames[i].intersects(frames[j])) }
        }
    }
}
