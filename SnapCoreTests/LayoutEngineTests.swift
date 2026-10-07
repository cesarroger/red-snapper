import XCTest
@testable import SnapCore

final class LayoutEngineTests: XCTestCase {
    // A 1440x900 display with a 25pt menu bar and a 70pt Dock at the bottom.
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)

    func testLeftHalfNoGap() {
        let r = LayoutEngine.frame(for: .leftHalf, in: visible, gap: 0)
        XCTAssertEqual(r, CGRect(x: 0, y: 70, width: 720, height: 805))
    }

    func testRightHalfNoGap() {
        let r = LayoutEngine.frame(for: .rightHalf, in: visible, gap: 0)
        XCTAssertEqual(r, CGRect(x: 720, y: 70, width: 720, height: 805))
    }

    func testHalvesWithGapLeaveEqualSpacingEverywhere() {
        let gap: CGFloat = 10
        let l = LayoutEngine.frame(for: .leftHalf, in: visible, gap: gap)
        let r = LayoutEngine.frame(for: .rightHalf, in: visible, gap: gap)
        XCTAssertEqual(l.minX, visible.minX + gap)          // outer gap on the left
        XCTAssertEqual(visible.maxX - r.maxX, gap)          // outer gap on the right
        XCTAssertEqual(r.minX - l.maxX, gap)                // inner gap between windows
        XCTAssertEqual(l.minY, visible.minY + gap)
        XCTAssertEqual(visible.maxY - l.maxY, gap)
        XCTAssertEqual(l.width, r.width)
    }

    func testTopHalfIsAboveBottomHalfInAppKitSpace() {
        let top = LayoutEngine.frame(for: .topHalf, in: visible, gap: 0)
        let bottom = LayoutEngine.frame(for: .bottomHalf, in: visible, gap: 0)
        XCTAssertEqual(top.maxY, visible.maxY)
        XCTAssertEqual(bottom.minY, visible.minY)
        XCTAssertEqual(top.minY, bottom.maxY)
        XCTAssertEqual(top.width, visible.width)
    }

    func testQuartersTileTheScreenExactly() {
        let quarters = SnapZone.fourUpOrder.map { LayoutEngine.frame(for: $0, in: visible, gap: 0) }
        let area = quarters.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, visible.width * visible.height, accuracy: 4 * 1440)
        let tl = quarters[0], br = quarters[3]
        XCTAssertEqual(tl.minX, visible.minX)
        XCTAssertEqual(tl.maxY, visible.maxY)
        XCTAssertEqual(br.maxX, visible.maxX)
        XCTAssertEqual(br.minY, visible.minY)
    }

    func testQuartersWithGapDoNotOverlap() {
        let quarters = SnapZone.fourUpOrder.map { LayoutEngine.frame(for: $0, in: visible, gap: 12) }
        for i in quarters.indices {
            for j in quarters.indices where j > i {
                XCTAssertFalse(quarters[i].intersects(quarters[j]), "\(i) overlaps \(j)")
            }
        }
    }

    func testThirds() {
        let w = CGRect(x: 0, y: 0, width: 1500, height: 900)
        XCTAssertEqual(LayoutEngine.frame(for: .leftThird, in: w, gap: 0), CGRect(x: 0, y: 0, width: 500, height: 900))
        XCTAssertEqual(LayoutEngine.frame(for: .centerThird, in: w, gap: 0), CGRect(x: 500, y: 0, width: 500, height: 900))
        XCTAssertEqual(LayoutEngine.frame(for: .rightThird, in: w, gap: 0), CGRect(x: 1000, y: 0, width: 500, height: 900))
    }

    func testThirdsWithGap() {
        let w = CGRect(x: 0, y: 0, width: 1540, height: 900)
        let gap: CGFloat = 10 // usable 1520 → 3 cells of 500 + 2 gaps of 10
        XCTAssertEqual(LayoutEngine.frame(for: .leftThird, in: w, gap: gap), CGRect(x: 10, y: 10, width: 500, height: 880))
        XCTAssertEqual(LayoutEngine.frame(for: .centerThird, in: w, gap: gap), CGRect(x: 520, y: 10, width: 500, height: 880))
        XCTAssertEqual(LayoutEngine.frame(for: .rightThird, in: w, gap: gap), CGRect(x: 1030, y: 10, width: 500, height: 880))
    }

    func testMaximizeRespectsGap() {
        XCTAssertEqual(LayoutEngine.frame(for: .maximize, in: visible, gap: 0), visible)
        XCTAssertEqual(LayoutEngine.frame(for: .maximize, in: visible, gap: 8), visible.insetBy(dx: 8, dy: 8))
    }

    func testCenterKeepsSize() {
        let r = LayoutEngine.frame(for: .center, in: visible, gap: 0, windowSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(r.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(r.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(r.midY, visible.midY, accuracy: 1)
    }

    func testCenterClampsOversizedWindow() {
        let r = LayoutEngine.frame(for: .center, in: visible, gap: 10, windowSize: CGSize(width: 5000, height: 5000))
        XCTAssertEqual(r, visible.insetBy(dx: 10, dy: 10))
    }

    func testSecondaryDisplayWithNegativeOrigin() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let r = LayoutEngine.frame(for: .rightHalf, in: left, gap: 0)
        XCTAssertEqual(r, CGRect(x: -960, y: -200, width: 960, height: 1080))
    }

    func testNegativeGapIsTreatedAsZero() {
        XCTAssertEqual(LayoutEngine.frame(for: .leftHalf, in: visible, gap: -5),
                       LayoutEngine.frame(for: .leftHalf, in: visible, gap: 0))
    }

    // MARK: - Minimum-size adjustment

    func testOversizedWindowInRightHalfStaysPinnedToRightEdge() {
        let target = LayoutEngine.frame(for: .rightHalf, in: visible, gap: 0)
        let adjusted = LayoutEngine.adjust(target: target, actualSize: CGSize(width: 900, height: 805), in: visible, gap: 0)
        XCTAssertEqual(adjusted.maxX, visible.maxX)
        XCTAssertEqual(adjusted.width, 900)
    }

    func testOversizedWindowInLeftHalfStaysPinnedToLeftEdge() {
        let target = LayoutEngine.frame(for: .leftHalf, in: visible, gap: 10)
        let adjusted = LayoutEngine.adjust(target: target, actualSize: CGSize(width: 900, height: 785), in: visible, gap: 10)
        XCTAssertEqual(adjusted.minX, target.minX)
    }

    func testOversizedWindowInCenterThirdIsCenteredOnZone() {
        let target = LayoutEngine.frame(for: .centerThird, in: visible, gap: 0)
        let adjusted = LayoutEngine.adjust(target: target, actualSize: CGSize(width: 600, height: 805), in: visible, gap: 0)
        XCTAssertEqual(adjusted.midX, target.midX, accuracy: 1)
    }

    func testTooTallWindowInBottomQuarterIsPushedUpButStaysOnScreen() {
        let target = LayoutEngine.frame(for: .bottomRight, in: visible, gap: 0)
        let adjusted = LayoutEngine.adjust(target: target, actualSize: CGSize(width: 720, height: 600), in: visible, gap: 0)
        XCTAssertEqual(adjusted.minY, visible.minY)             // pinned to the bottom edge
        XCTAssertLessThanOrEqual(adjusted.maxY, visible.maxY)
    }

    func testWindowLargerThanScreenIsPinnedTopLeft() {
        let target = LayoutEngine.frame(for: .rightHalf, in: visible, gap: 0)
        let adjusted = LayoutEngine.adjust(target: target, actualSize: CGSize(width: 2000, height: 1200), in: visible, gap: 0)
        XCTAssertEqual(adjusted.minX, visible.minX)
        XCTAssertEqual(adjusted.maxY, visible.maxY)
    }

    func testMatchesZone() {
        let r = LayoutEngine.frame(for: .leftHalf, in: visible, gap: 6)
        XCTAssertTrue(LayoutEngine.frame(r, matches: .leftHalf, in: visible, gap: 6))
        XCTAssertFalse(LayoutEngine.frame(r, matches: .rightHalf, in: visible, gap: 6))
        XCTAssertFalse(LayoutEngine.frame(r, matches: .center, in: visible, gap: 6))
    }
}
