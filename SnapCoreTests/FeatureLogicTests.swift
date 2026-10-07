import XCTest
@testable import SnapCore
import Carbon.HIToolbox

final class NewZoneTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 1500, height: 900)

    func testTwoThirdsAndThirdsCompose() {
        let lt = LayoutEngine.frame(for: .leftTwoThirds, in: visible, gap: 0)
        let r = LayoutEngine.frame(for: .rightThird, in: visible, gap: 0)
        XCTAssertEqual(lt, CGRect(x: 0, y: 0, width: 1000, height: 900))
        XCTAssertEqual(lt.maxX, r.minX)
        XCTAssertEqual(LayoutEngine.frame(for: .rightTwoThirds, in: visible, gap: 0), CGRect(x: 500, y: 0, width: 1000, height: 900))
    }

    func testVerticalThirdsInAppKitSpace() {
        XCTAssertEqual(LayoutEngine.frame(for: .topThird, in: visible, gap: 0), CGRect(x: 0, y: 600, width: 1500, height: 300))
        XCTAssertEqual(LayoutEngine.frame(for: .topTwoThirds, in: visible, gap: 0), CGRect(x: 0, y: 300, width: 1500, height: 600))
        XCTAssertEqual(LayoutEngine.frame(for: .bottomThird, in: visible, gap: 0), CGRect(x: 0, y: 0, width: 1500, height: 300))
        XCTAssertEqual(LayoutEngine.frame(for: .bottomTwoThirds, in: visible, gap: 0), CGRect(x: 0, y: 0, width: 1500, height: 600))
    }

    func testTwoThirdsWithGapKeepsInnerGap() {
        let gap: CGFloat = 10
        let lt = LayoutEngine.frame(for: .leftTwoThirds, in: CGRect(x: 0, y: 0, width: 1540, height: 900), gap: gap)
        let r = LayoutEngine.frame(for: .rightThird, in: CGRect(x: 0, y: 0, width: 1540, height: 900), gap: gap)
        XCTAssertEqual(r.minX - lt.maxX, gap)
        XCTAssertEqual(lt.width, 1010) // two cells of 500 + one inner gap
    }
}

final class SnapCycleTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 1500, height: 900)
    func frame(_ z: SnapZone) -> CGRect { LayoutEngine.frame(for: z, in: visible, gap: 0) }

    func decide(_ zone: SnapZone, from current: CGRect, cycle: Bool = true, hop: Bool = true,
                left: Bool = false, right: Bool = false) -> SnapCycle.Decision {
        SnapCycle.decide(pressed: zone, currentFrame: current, visibleFrame: visible, gap: 0,
                         cycleSizes: cycle, hopDisplays: hop,
                         hasDisplay: { $0 == .left ? left : right })
    }

    func testFirstPressSnaps() {
        XCTAssertEqual(decide(.leftHalf, from: CGRect(x: 100, y: 100, width: 300, height: 300)), .snap(.leftHalf))
    }

    func testCycleHalfTwoThirdsThirdThenWrap() {
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftHalf)), .snap(.leftTwoThirds))
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftTwoThirds)), .snap(.leftThird))
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftThird)), .snap(.leftHalf))
    }

    func testEndOfCycleHopsToDisplayOnThatSide() {
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftThird), left: true), .hop(.left, .rightHalf))
        XCTAssertEqual(decide(.rightHalf, from: frame(.rightThird), right: true), .hop(.right, .leftHalf))
        // A display on the *other* side doesn't count.
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftThird), right: true), .snap(.leftHalf))
    }

    func testCyclingOffHopsStraightFromHalf() {
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftHalf), cycle: false, left: true), .hop(.left, .rightHalf))
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftHalf), cycle: false), .snap(.leftHalf))
    }

    func testHopOffKeepsCycling() {
        XCTAssertEqual(decide(.leftHalf, from: frame(.leftThird), hop: false, left: true), .snap(.leftHalf))
    }

    func testVerticalAndThirdCycles() {
        XCTAssertEqual(decide(.topHalf, from: frame(.topHalf)), .snap(.topTwoThirds))
        XCTAssertEqual(decide(.bottomHalf, from: frame(.bottomTwoThirds)), .snap(.bottomThird))
        XCTAssertEqual(decide(.leftThird, from: frame(.leftThird)), .snap(.leftTwoThirds))
        XCTAssertEqual(decide(.leftThird, from: frame(.leftTwoThirds)), .snap(.leftThird))
    }

    func testNonCyclingZonesJustSnap() {
        XCTAssertEqual(decide(.maximize, from: frame(.maximize), left: true), .snap(.maximize))
        XCTAssertEqual(decide(.topLeft, from: frame(.topLeft)), .snap(.topLeft))
    }
}

final class NeighborScreenTests: XCTestCase {
    let primary = CGRect(x: 0, y: 0, width: 1280, height: 832)
    let leftBig = CGRect(x: -2560, y: 432, width: 2560, height: 1440)
    let right = CGRect(x: 1280, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 832, width: 1280, height: 800)

    func testDirectNeighbors() {
        let frames = [primary, leftBig, right, above]
        XCTAssertEqual(ScreenMath.neighborIndex(of: 0, direction: .left, screenFrames: frames), 1)
        XCTAssertEqual(ScreenMath.neighborIndex(of: 0, direction: .right, screenFrames: frames), 2)
        XCTAssertNil(ScreenMath.neighborIndex(of: 1, direction: .left, screenFrames: frames))
        XCTAssertNil(ScreenMath.neighborIndex(of: 2, direction: .right, screenFrames: frames))
    }

    func testDisplayAboveIsNotASideNeighbor() {
        XCTAssertNil(ScreenMath.neighborIndex(of: 0, direction: .left, screenFrames: [primary, above]))
        XCTAssertNil(ScreenMath.neighborIndex(of: 0, direction: .right, screenFrames: [primary, above]))
    }

    func testPrefersOverlappingThenNearest() {
        let farOverlapping = CGRect(x: 4000, y: 0, width: 1000, height: 832)
        let nearNonOverlapping = CGRect(x: 1280, y: 2000, width: 1000, height: 800)
        XCTAssertEqual(ScreenMath.neighborIndex(of: 0, direction: .right, screenFrames: [primary, nearNonOverlapping, farOverlapping]), 2)
    }
}

final class DragRestoreTests: XCTestCase {
    func testKeepsCursorAtSameRelativeX() {
        let snapped = CGRect(x: 0, y: 28, width: 640, height: 804)
        let cursor = CGPoint(x: 320, y: 40) // middle of the title bar
        let r = DragRestore.frame(from: snapped, originalSize: CGSize(width: 400, height: 300), cursor: cursor)
        XCTAssertEqual(r, CGRect(x: 120, y: 28, width: 400, height: 300))
        XCTAssertEqual(r.midX, cursor.x)
    }

    func testCursorNearLeftEdgeStaysNearLeftEdge() {
        let r = DragRestore.frame(from: CGRect(x: 100, y: 0, width: 1000, height: 500),
                                  originalSize: CGSize(width: 200, height: 200), cursor: CGPoint(x: 150, y: 10))
        XCTAssertEqual(r.minX, 140) // 5% in → 10pt of the 200pt window
    }

    func testUnchanged() {
        let f = CGRect(x: 0, y: 28, width: 640, height: 804)
        XCTAssertTrue(DragRestore.isUnchanged(f.offsetBy(dx: 1, dy: 0), since: f))
        XCTAssertFalse(DragRestore.isUnchanged(f.offsetBy(dx: 30, dy: 0), since: f))
    }
}

final class LayoutMatcherTests: XCTestCase {
    func saved(_ bundle: String, _ title: String, _ order: Int) -> SavedWindow {
        SavedWindow(bundleID: bundle, appName: bundle, title: title, order: order, displayID: "D",
                    displayVisibleFrame: .zero, frame: .zero)
    }

    func testExactTitleWinsOverOrder() {
        let s = [saved("ed", "notes.txt", 0), saved("ed", "todo.txt", 1)]
        let o = [LayoutMatcher.OpenWindow(id: 1, bundleID: "ed", title: "todo.txt", order: 0),
                 LayoutMatcher.OpenWindow(id: 2, bundleID: "ed", title: "notes.txt", order: 1)]
        XCTAssertEqual(LayoutMatcher.match(saved: s, open: o), [0: 2, 1: 1])
    }

    func testFallsBackToOrderWithinSameApp() {
        let s = [saved("web", "Old page", 0), saved("web", "Other old page", 1), saved("chat", "", 0)]
        let o = [LayoutMatcher.OpenWindow(id: 7, bundleID: "web", title: "New B", order: 1),
                 LayoutMatcher.OpenWindow(id: 6, bundleID: "web", title: "New A", order: 0),
                 LayoutMatcher.OpenWindow(id: 9, bundleID: "chat", title: "Inbox", order: 0)]
        XCTAssertEqual(LayoutMatcher.match(saved: s, open: o), [0: 6, 1: 7, 2: 9])
    }

    func testMissingAppsAndExtraWindowsAreLeftAlone() {
        let s = [saved("gone", "x", 0), saved("ed", "a", 0)]
        let o = [LayoutMatcher.OpenWindow(id: 1, bundleID: "ed", title: "a", order: 0),
                 LayoutMatcher.OpenWindow(id: 2, bundleID: "ed", title: "b", order: 1)]
        XCTAssertEqual(LayoutMatcher.match(saved: s, open: o), [1: 1])
    }

    func testEachWindowUsedOnce() {
        let s = [saved("ed", "a", 0), saved("ed", "a", 1)]
        let o = [LayoutMatcher.OpenWindow(id: 1, bundleID: "ed", title: "a", order: 0)]
        XCTAssertEqual(LayoutMatcher.match(saved: s, open: o).count, 1)
    }

    func testAppNamesDeduplicated() {
        let layout = SavedLayout(name: "Work", windows: [saved("a", "", 0), saved("b", "", 0), saved("a", "", 1)])
        XCTAssertEqual(layout.appNames, ["a", "b"])
    }
}

final class PreferencesStoreTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        suite = "RedSnapperTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.gap, 0)
        XCTAssertTrue(store.bool(PreferencesStore.Key.hotKeysEnabled))
        XCTAssertTrue(store.bool(PreferencesStore.Key.cycleSizes))
        XCTAssertEqual(store.bindings, HotKeyAction.defaultBindings)
        XCTAssertEqual(store.layouts, [])
        XCTAssertEqual(store.excludedBundleIDs, [])
    }

    func testValuesSurviveANewStore() {
        let store = PreferencesStore(defaults: defaults)
        store.gap = 14
        store.set(false, for: PreferencesStore.Key.dragToSnapEnabled)
        store.excludedBundleIDs = ["com.b", "com.a", "com.b"]

        let reloaded = PreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.gap, 14)
        XCTAssertFalse(reloaded.bool(PreferencesStore.Key.dragToSnapEnabled))
        XCTAssertEqual(reloaded.excludedBundleIDs, ["com.a", "com.b"])
    }

    func testNegativeGapIsClamped() {
        let store = PreferencesStore(defaults: defaults)
        store.gap = -5
        XCTAssertEqual(store.gap, 0)
    }

    func testChangedAndClearedShortcutsPersist() {
        let store = PreferencesStore(defaults: defaults)
        var b = store.bindings
        b[.leftHalf] = KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: KeyCombo.control | KeyCombo.shift)
        b[.center] = nil
        store.bindings = b

        let reloaded = PreferencesStore(defaults: UserDefaults(suiteName: suite)!).bindings
        XCTAssertEqual(reloaded[.leftHalf], KeyCombo(keyCode: UInt32(kVK_ANSI_H), modifiers: KeyCombo.control | KeyCombo.shift))
        XCTAssertNil(reloaded[.center], "a cleared shortcut must not come back as the default")
        XCTAssertEqual(reloaded[.rightHalf], HotKeyAction.defaultBindings[.rightHalf])
    }

    func testNewActionsGetDefaultsWhenMissingFromStoredData() throws {
        // Simulate data saved by an older version that didn't know about `restore`.
        let old: [String: KeyCombo?] = ["leftHalf": HotKeyAction.defaultBindings[.leftHalf]]
        defaults.set(try JSONEncoder().encode(old), forKey: PreferencesStore.Key.bindings)
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.bindings[.restore], HotKeyAction.defaultBindings[.restore])
    }

    func testCorruptBindingsFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: PreferencesStore.Key.bindings)
        XCTAssertEqual(PreferencesStore(defaults: defaults).bindings, HotKeyAction.defaultBindings)
    }

    func testLayoutsRoundTrip() {
        let store = PreferencesStore(defaults: defaults)
        let w = SavedWindow(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: "a", order: 0,
                            displayID: "X", displayVisibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 804),
                            frame: CGRect(x: 0, y: 0, width: 640, height: 804))
        let layout = SavedLayout(name: "Coding", windows: [w], hotKey: KeyCombo(keyCode: 18, modifiers: KeyCombo.control))
        store.layouts = [layout]
        XCTAssertEqual(PreferencesStore(defaults: UserDefaults(suiteName: suite)!).layouts, [layout])
    }
}
