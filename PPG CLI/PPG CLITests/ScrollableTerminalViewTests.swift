@testable import PPG_CLI
import XCTest

final class ScrollableTerminalViewTests: XCTestCase {
    func testScrollTickCalculation() {
        // The formula used in flushScrollDelta():
        //   max(1, Int(abs(delta) / pixelsPerScrollTick))
        let pixelsPerTick: CGFloat = 30
        XCTAssertEqual(max(1, Int(abs(15.0) / pixelsPerTick)), 1, "Small delta → 1 tick")
        XCTAssertEqual(max(1, Int(abs(30.0) / pixelsPerTick)), 1, "Exact 1 tick boundary")
        XCTAssertEqual(max(1, Int(abs(90.0) / pixelsPerTick)), 3, "3x delta → 3 ticks")
        XCTAssertEqual(max(1, Int(abs(0.5) / pixelsPerTick)), 1, "Tiny delta → minimum 1 tick")
        XCTAssertEqual(max(1, Int(abs(-60.0) / pixelsPerTick)), 2, "Negative delta → 2 ticks")
    }
}
