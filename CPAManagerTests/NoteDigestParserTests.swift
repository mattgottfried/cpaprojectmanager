import XCTest
@testable import CPAManager

final class NoteDigestParserTests: XCTestCase {
    func testSplitsLinesAndStripsMarkers() {
        let note = """
        - Call Smith about the 1099s
        • Send engagement letter to Jones LLC
        1. Reschedule Tuesday meeting
        ☐ Ask Dana for K-1
        """
        let texts = NoteDigestParser.candidates(from: note).map { $0.text }
        XCTAssertEqual(texts, [
            "Call Smith about the 1099s",
            "Send engagement letter to Jones LLC",
            "Reschedule Tuesday meeting",
            "Ask Dana for K-1",
        ])
    }

    func testFlagsCheckedItems() {
        let note = "- [x] Paid invoice 1042\n- [ ] Follow up with Lee"
        let result = NoteDigestParser.candidates(from: note)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isChecked)
        XCTAssertFalse(result[1].isChecked)
        XCTAssertEqual(result[0].text, "Paid invoice 1042")
    }

    func testDropsHeadingsSeparatorsAndTinyLines() {
        let note = "# Messages\nToday:\n-----\nok\nText from Pat: needs W-2 copy"
        let texts = NoteDigestParser.candidates(from: note).map { $0.text }
        XCTAssertEqual(texts, ["Text from Pat: needs W-2 copy"])
    }

    func testDedupesWithinAPaste() {
        let note = "Call Smith\n- call smith!\nCALL   SMITH"
        XCTAssertEqual(NoteDigestParser.candidates(from: note).count, 1)
    }

    func testKeepsYearLikeNumbersThatAreNotListMarkers() {
        let texts = NoteDigestParser.candidates(from: "2025 return for Smith").map { $0.text }
        XCTAssertEqual(texts, ["2025 return for Smith"])
    }

    func testDedupeKeyIgnoresCasePunctuationAndSpacing() {
        XCTAssertEqual(
            NoteDigestParser.dedupeKey("  Call Smith — re: 1099s! "),
            NoteDigestParser.dedupeKey("call smith re 1099s")
        )
    }

    func testHandlesWindowsLineEndings() {
        XCTAssertEqual(NoteDigestParser.candidates(from: "First thing\r\nSecond thing").count, 2)
    }
}
