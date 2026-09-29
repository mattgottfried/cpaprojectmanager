import XCTest
@testable import CPAManager

final class QuickAddParserTests: XCTestCase {
    func testPlainTextHasNoDate() {
        let result = QuickAddParser.parse("Call the office")
        XCTAssertEqual(result.title, "Call the office")
        XCTAssertNil(result.dueDate)
    }

    func testEmptyInput() {
        XCTAssertEqual(QuickAddParser.parse("   ").title, "")
    }

    func testTrailingExplicitDateIsExtracted() {
        let result = QuickAddParser.parse("Send 1099s on December 15, 2099")
        XCTAssertEqual(result.title, "Send 1099s")
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: result.dueDate ?? .distantPast)
        XCTAssertEqual(comps.year, 2099)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 15)
    }

    func testWholeLineThatIsOnlyADateStaysAsText() {
        let result = QuickAddParser.parse("December 15, 2099")
        XCTAssertEqual(result.title, "December 15, 2099")
        XCTAssertNil(result.dueDate)
    }
}
