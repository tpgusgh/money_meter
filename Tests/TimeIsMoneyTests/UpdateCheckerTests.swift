import XCTest
@testable import TimeIsMoney

final class UpdateCheckerTests: XCTestCase {
    func testIsNewerComparesNumericallyNotLexically() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.9", than: "1.0.10"))
    }

    func testIsNewerHandlesEqualAndDifferentLengths() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.4", than: "1.0.4"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.1"))
    }
}
