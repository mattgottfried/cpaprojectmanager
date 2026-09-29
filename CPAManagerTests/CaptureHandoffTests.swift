import XCTest
@testable import CPAManager

final class CaptureHandoffTests: XCTestCase {
    func testQueueRoundTripsThroughJSON() throws {
        let captures = [
            PendingCapture(text: "Q3 numbers — Dana", sourceRaw: "email", link: "https://mail.google.com/x"),
            PendingCapture(text: "", sourceRaw: "note", attachmentName: "1A2B3C4D-Statement.pdf"),
        ]
        let data = try XCTUnwrap(PendingCaptures.encode(captures))
        XCTAssertEqual(PendingCaptures.decode(data), captures)
        XCTAssertEqual(PendingCaptures.decode(nil), [])
        XCTAssertEqual(PendingCaptures.decode(Data("not json".utf8)), [])
    }

    func testDisplayPartsDropTheUniquenessPrefix() {
        let parts = PendingCaptures.displayParts("1A2B3C4D-Q3 Statement.PDF")
        XCTAssertEqual(parts.base, "Q3 Statement")
        XCTAssertEqual(parts.ext, "pdf")
        // A name whose first dash isn't at position 8 is left alone.
        let plain = PendingCaptures.displayParts("my-file.png")
        XCTAssertEqual(plain.base, "my-file")
        XCTAssertEqual(plain.ext, "png")
        XCTAssertEqual(PendingCaptures.displayParts("noextension").ext, "")
    }

    func testAttachmentURLIsNilForEmptyName() {
        XCTAssertNil(PendingCaptures.attachmentURL(""))
    }

    func testPendingCaptureDefaultsToEmail() {
        let capture = PendingCapture(text: "hi")
        XCTAssertEqual(capture.sourceRaw, "email")
        XCTAssertNotNil(InboxSource(rawValue: capture.sourceRaw))
    }
}
