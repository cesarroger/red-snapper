import XCTest
@testable import SnapCore
import Carbon.HIToolbox

final class CoordinateConverterTests: XCTestCase {
    let conv = CoordinateConverter(primaryScreenHeight: 900)

    func testLeftHalfOfPrimaryUnderMenuBar() {
        // AppKit visible frame of the left half on a 1440x900 screen with 25pt menu bar, no Dock.
        let appKit = CGRect(x: 0, y: 0, width: 720, height: 875)
        XCTAssertEqual(conv.toAX(appKit), CGRect(x: 0, y: 25, width: 720, height: 875))
    }

    func testRoundTrip() {
        let r = CGRect(x: -300, y: 1234, width: 640, height: 480)
        XCTAssertEqual(conv.toAppKit(conv.toAX(r)), r)
    }

    func testDisplayAbovePrimaryHasNegativeAXY() {
        // A 1080pt-tall display stacked directly above the primary.
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(conv.toAX(above).minY, -1080)
    }

    func testPoints() {
        XCTAssertEqual(conv.toAX(CGPoint(x: 10, y: 900)), CGPoint(x: 10, y: 0))
        XCTAssertEqual(conv.toAppKit(CGPoint(x: 10, y: 0)), CGPoint(x: 10, y: 900))
    }
}

final class ScreenMathTests: XCTestCase {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
    let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)

    func testScreenWithLargestOverlapWins() {
        let window = CGRect(x: 1300, y: 100, width: 400, height: 300) // 140pt on primary, 260 on right
        XCTAssertEqual(ScreenMath.screenIndex(for: window, screenFrames: [primary, right]), 1)
    }

    func testOffscreenWindowFallsBackToNearestScreen() {
        let window = CGRect(x: 5000, y: 0, width: 100, height: 100)
        XCTAssertEqual(ScreenMath.screenIndex(for: window, screenFrames: [primary, right]), 1)
    }

    func testSpatialOrderIsLeftToRight() {
        XCTAssertEqual(ScreenMath.spatialOrder(of: [primary, right, left]), [2, 0, 1])
    }

    func testAdjacentScreenWraps() {
        let frames = [primary, right, left]
        XCTAssertEqual(ScreenMath.adjacentScreenIndex(from: 1, screenFrames: frames, forward: true), 2)
        XCTAssertEqual(ScreenMath.adjacentScreenIndex(from: 2, screenFrames: frames, forward: false), 1)
        XCTAssertEqual(ScreenMath.adjacentScreenIndex(from: 0, screenFrames: frames, forward: true), 1)
        XCTAssertNil(ScreenMath.adjacentScreenIndex(from: 0, screenFrames: [primary], forward: true))
    }

    func testRelocatePreservesRelativePositionAndSize() {
        let src = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let dst = CGRect(x: 1000, y: 0, width: 2000, height: 500)
        let window = CGRect(x: 500, y: 250, width: 500, height: 500) // right half, middle
        XCTAssertEqual(ScreenMath.relocate(window, from: src, to: dst), CGRect(x: 2000, y: 125, width: 1000, height: 250))
    }

    func testRelocateClampsInsideDestination() {
        let src = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let dst = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let window = CGRect(x: 900, y: -50, width: 300, height: 300) // hanging off the source
        let r = ScreenMath.relocate(window, from: src, to: dst)
        XCTAssertTrue(dst.contains(r), "\(r) not inside \(dst)")
    }
}

final class DragZoneDetectorTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1500, height: 900)
    let d = DragZoneDetector(edgeThreshold: 5, cornerSize: 50)

    func testEdges() {
        XCTAssertEqual(d.zone(for: CGPoint(x: 0, y: 450), screenFrame: screen), .leftHalf)
        XCTAssertEqual(d.zone(for: CGPoint(x: 1499, y: 450), screenFrame: screen), .rightHalf)
        XCTAssertEqual(d.zone(for: CGPoint(x: 750, y: 900), screenFrame: screen), .maximize)
    }

    func testBottomEdgeThirds() {
        XCTAssertEqual(d.zone(for: CGPoint(x: 200, y: 0), screenFrame: screen), .leftThird)
        XCTAssertEqual(d.zone(for: CGPoint(x: 750, y: 0), screenFrame: screen), .centerThird)
        XCTAssertEqual(d.zone(for: CGPoint(x: 1300, y: 0), screenFrame: screen), .rightThird)
    }

    func testCorners() {
        XCTAssertEqual(d.zone(for: CGPoint(x: 0, y: 880), screenFrame: screen), .topLeft)
        XCTAssertEqual(d.zone(for: CGPoint(x: 30, y: 900), screenFrame: screen), .topLeft)
        XCTAssertEqual(d.zone(for: CGPoint(x: 1500, y: 899), screenFrame: screen), .topRight)
        XCTAssertEqual(d.zone(for: CGPoint(x: 2, y: 10), screenFrame: screen), .bottomLeft)
        XCTAssertEqual(d.zone(for: CGPoint(x: 1480, y: 0), screenFrame: screen), .bottomRight)
    }

    func testInteriorIsNoZone() {
        XCTAssertNil(d.zone(for: CGPoint(x: 750, y: 450), screenFrame: screen))
        XCTAssertNil(d.zone(for: CGPoint(x: 6, y: 450), screenFrame: screen))
    }

    func testWorksOnOffsetScreen() {
        let s = CGRect(x: -1280, y: 100, width: 1280, height: 800)
        XCTAssertEqual(d.zone(for: CGPoint(x: -1280, y: 500), screenFrame: s), .leftHalf)
        XCTAssertEqual(d.zone(for: CGPoint(x: -1, y: 500), screenFrame: s), .rightHalf)
    }
}

final class HotKeyModelTests: XCTestCase {
    func testDisplayString() {
        let combo = KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: KeyCombo.control | KeyCombo.option)
        XCTAssertEqual(combo.displayString, "⌃⌥←")
    }

    func testDefaultsAreUniqueAndCoverEverythingButTwoThirds() {
        let defaults = HotKeyAction.defaultBindings
        XCTAssertEqual(Set(defaults.values).count, defaults.count)
        let unbound = Set(HotKeyAction.allCases).subtracting(defaults.keys)
        XCTAssertEqual(unbound, [.leftTwoThirds, .rightTwoThirds])
    }

    func testZoneMapping() {
        XCTAssertEqual(HotKeyAction.leftHalf.zone, .leftHalf)
        XCTAssertNil(HotKeyAction.fourUpGrid.zone)
        XCTAssertNil(HotKeyAction.nextDisplay.zone)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(HotKeyAction.defaultBindings)
        let decoded = try JSONDecoder().decode([HotKeyAction: KeyCombo].self, from: data)
        XCTAssertEqual(decoded, HotKeyAction.defaultBindings)
    }
}
