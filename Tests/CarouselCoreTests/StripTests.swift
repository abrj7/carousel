import CoreGraphics
import XCTest
@testable import CarouselCore

final class StripTests: XCTestCase {
    let gap = 8.0
    let viewport = CGRect(x: 0, y: 25, width: 1000, height: 700)

    func strip(_ ids: [WindowID], width: Double = 0.5) -> Strip {
        var s = Strip()
        for id in ids { s.insert(id, width: width, at: s.columns.count) }
        return s
    }

    // MARK: Membership and focus

    func testInsertGoesRightOfFocusAndKeepsFocus() {
        var s = strip([1, 2, 3])
        s.focus(2)
        s.insert(9, width: 0.5)
        XCTAssertEqual(s.windows, [1, 2, 9, 3])
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testInsertAtFrontShiftsFocusIndex() {
        var s = strip([1, 2])
        s.focus(2)
        s.insert(9, width: 0.5, at: 0)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testRemoveFocusedLastColumnFocusesLeftNeighbour() {
        var s = strip([1, 2, 3])
        s.focus(3)
        s.remove(3)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testRemoveColumnLeftOfFocusKeepsFocusedWindow() {
        var s = strip([1, 2, 3])
        s.focus(3)
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 3)
    }

    func testRemoveLastWindowEmptiesStrip() {
        var s = strip([1])
        s.remove(1)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.focusedWindow)
    }

    func testFocusNavigationClampsAtEnds() {
        var s = strip([1, 2, 3])
        s.focusFirst(); s.focusLeft()
        XCTAssertEqual(s.focusedWindow, 1)
        s.focusLast(); s.focusRight()
        XCTAssertEqual(s.focusedWindow, 3)
    }

    func testMoveSwapsColumnsAndFollowsWindow() {
        var s = strip([1, 2, 3])
        s.focus(1)
        s.moveRight()
        XCTAssertEqual(s.windows, [2, 1, 3])
        XCTAssertEqual(s.focusedWindow, 1)
    }

    func testReorderKeepsFocusOnSameWindow() {
        var s = strip([1, 2, 3])
        s.focus(2)
        s.reorder(from: 0, to: 2)
        XCTAssertEqual(s.windows, [2, 3, 1])
        XCTAssertEqual(s.focusedWindow, 2)
    }

    // MARK: Stacks

    func testStackLeftMergesAndRemovesEmptyColumn() {
        var s = strip([1, 2, 3])
        s.focus(2)
        s.stack(direction: -1)
        XCTAssertEqual(s.columns.count, 2)
        XCTAssertEqual(s.columns[0].windows, [1, 2])
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testStackRightFixesTargetIndexAfterRemoval() {
        var s = strip([1, 2, 3])
        s.focus(1)
        s.stack(direction: 1)
        XCTAssertEqual(s.columns.map(\.windows), [[2, 1], [3]])
        XCTAssertEqual(s.focusedColumn, 0)
        XCTAssertEqual(s.focusedWindow, 1)
    }

    func testPopOutRestoresSeparateColumn() {
        var s = strip([1, 2])
        s.focus(2)
        s.stack(direction: -1)
        s.popOut(direction: 1)
        XCTAssertEqual(s.columns.map(\.windows), [[1], [2]])
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testFocusUpDownInsideStack() {
        var s = strip([1, 2, 3])
        s.focus(2); s.stack(direction: -1)
        s.focus(3); s.stack(direction: -1)
        XCTAssertEqual(s.focusedWindow, 3)
        s.focusUp()
        XCTAssertEqual(s.focusedWindow, 2)
        s.moveUp()
        XCTAssertEqual(s.columns[0].windows, [2, 1, 3])
    }

    // MARK: Sizing

    func testCycleWidthWraps() {
        var s = strip([1], width: 0.5)
        let presets = [0.25, 0.5, 0.75]
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.75)
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.25)
    }

    func testFullWidthToggleRestoresPreviousWidth() {
        var s = strip([1], width: 0.33)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 1)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 0.33)
    }

    func testPixelWidthRoundTrips() {
        let px = Strip.pixelWidth(0.4, viewportWidth: 1000, gap: gap)
        XCTAssertEqual(Strip.fraction(forPixelWidth: px, viewportWidth: 1000, gap: gap), 0.4, accuracy: 1e-9)
    }

    // MARK: Geometry

    func testTwoHalfColumnsFillViewportExactly() {
        let s = strip([1, 2])
        XCTAssertEqual(s.totalWidth(viewportWidth: 1000, gap: gap), 1000, accuracy: 1e-9)
        let frames = s.frames(in: viewport, gap: gap)
        XCTAssertEqual(frames[0].frame.minX, 8)
        XCTAssertEqual(frames[1].frame.maxX, 992)
        XCTAssertEqual(frames[0].frame.minY, 33)
        XCTAssertEqual(frames[0].frame.height, 684)
    }

    func testStackedWindowsSplitHeightWithGaps() {
        var s = strip([1, 2])
        s.focus(2); s.stack(direction: -1)
        let frames = s.frames(in: viewport, gap: gap)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].frame.minX, frames[1].frame.minX)
        XCTAssertEqual(frames[1].frame.minY - frames[0].frame.maxY, gap, accuracy: 1)
        XCTAssertEqual(frames[1].frame.maxY, viewport.maxY - gap, accuracy: 1)
    }

    func testNeverModeScrollsMinimallyToRevealFocused() {
        var s = strip([1, 2, 3, 4])
        s.focusLast()
        s.scrollToFocused(viewportWidth: 1000, gap: gap, mode: .never)
        XCTAssertTrue(s.isFullyVisible(3, viewportWidth: 1000, gap: gap))
        XCTAssertEqual(s.offset, s.totalWidth(viewportWidth: 1000, gap: gap) - 1000, accuracy: 1e-9)
        // Moving left by one: column 2 is already visible, so nothing scrolls.
        let before = s.offset
        s.focusLeft()
        s.scrollToFocused(viewportWidth: 1000, gap: gap, mode: .never)
        XCTAssertEqual(s.offset, before)
    }

    func testNeverModeLeavesManualCentreAlone() {
        var s = strip([1, 2, 3])
        s.focus(1)
        s.centreFocused(viewportWidth: 1000, gap: gap)
        let centred = s.offset
        XCTAssertLessThan(centred, 0)
        s.scrollToFocused(viewportWidth: 1000, gap: gap, mode: .never)
        XCTAssertEqual(s.offset, centred)
    }

    func testAlwaysModeCentresFocusedColumn() {
        var s = strip([1, 2, 3], width: 0.33)
        s.focus(2)
        s.scrollToFocused(viewportWidth: 1000, gap: gap, mode: .always)
        let f = s.frames(in: viewport, gap: gap)[1].frame
        XCTAssertEqual(Double(f.midX), 500, accuracy: 1)
    }

    func testOnOverflowLeftAlignsWhenEverythingFits() {
        var s = strip([1, 2], width: 0.33)
        s.focusLast()
        s.scrollToFocused(viewportWidth: 1000, gap: gap, mode: .onOverflow)
        XCTAssertEqual(s.offset, 0)
    }

    func testSnapAlignsNearestColumnAndMovesFocusIfHidden() {
        var s = strip([1, 2, 3, 4])
        s.focusFirst()
        s.offset = 1010 // a little past column 2's left edge
        s.snap(viewportWidth: 1000, gap: gap, mode: .never)
        let lefts = s.lefts(viewportWidth: 1000, gap: gap)
        XCTAssertEqual(s.offset, lefts[2] - gap, accuracy: 1e-9)
        XCTAssertEqual(s.focusedColumn, 2)
    }

    func testSnapKeepsFocusWhenStillVisible() {
        var s = strip([1, 2, 3, 4])
        s.focus(2)
        s.offset = 10
        s.snap(viewportWidth: 1000, gap: gap, mode: .never)
        XCTAssertEqual(s.offset, 0)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    // MARK: Parking

    func testParkPushesOffscreenWindowsToEdges() {
        let vp = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = park(CGRect(x: 1500, y: 10, width: 400, height: 700), in: vp)
        XCTAssertEqual(right.side, .right)
        XCTAssertEqual(right.frame.minX, 999)
        let left = park(CGRect(x: -900, y: 10, width: 400, height: 700), in: vp)
        XCTAssertEqual(left.side, .left)
        XCTAssertEqual(left.frame.maxX, 1)
        let partial = park(CGRect(x: 800, y: 10, width: 400, height: 700), in: vp)
        XCTAssertEqual(partial.side, .none)
        XCTAssertEqual(partial.frame.minX, 800)
    }
}
