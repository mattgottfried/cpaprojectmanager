import XCTest
@testable import CPAManager

final class DriveFolderTemplateTests: XCTestCase {
    func testStandardLayoutMatchesTheOwnersFolders() {
        let t = DriveFolderTemplate.standard
        XCTAssertEqual(t.slots.map(\.code), ["00", "01", "02", "03", "04"])
        XCTAssertEqual(t.slots.first { $0.id == "deliverables" }?.yearFolders, true)
        XCTAssertEqual(t.slots.filter(\.yearFolders).count, 1)
        XCTAssertTrue(t.problems.isEmpty)
    }

    func testRoutingByKindAndYear() {
        let t = DriveFolderTemplate.standard
        XCTAssertEqual(t.path(for: .deliverable, year: 2025), ["03 - Deliverables", "2025"])
        XCTAssertEqual(t.path(for: .upload, year: 2025), ["02 - Source Documents (Client Uploads)"])
        XCTAssertEqual(t.path(for: .letter, year: 2025), ["04 - Invoices & Engagements"])
        XCTAssertEqual(t.path(for: .invoice, year: 2025), t.path(for: .quote, year: 2025))
        XCTAssertEqual(t.path(for: .other, year: 2025), [], "unrouted kinds go in the client's own folder")
    }

    func testARouteToAMissingSlotFallsBackToTheClientFolder() {
        var t = DriveFolderTemplate.standard
        t.routes[DocumentKind.upload.rawValue] = "gone"
        XCTAssertEqual(t.path(for: .upload, year: 2025), [])
    }

    func testTemplateRoundTripsAndBadJSONFallsBack() {
        var t = DriveFolderTemplate.standard
        t.namePattern = "{client} {title}"
        t.slots.append(ClientFolderSlot(name: "05 - Notices"))
        XCTAssertEqual(DriveFolderTemplate.decode(t.encoded()), t)
        XCTAssertEqual(DriveFolderTemplate.decode(""), .standard)
        XCTAssertEqual(DriveFolderTemplate.decode("not json"), .standard)
        XCTAssertEqual(DriveFolderTemplate.decode(#"{"slots":[],"routes":{},"namePattern":""}"#), .standard, "no folders at all is unusable")
    }

    func testProblemsFlagBlankAndDuplicateNames() {
        var t = DriveFolderTemplate.standard
        t.slots.append(ClientFolderSlot(name: "  "))
        t.slots.append(ClientFolderSlot(name: "00 - permanent"))
        XCTAssertEqual(t.problems.count, 2)
    }

    func testKindInferenceForExistingFiles() {
        XCTAssertEqual(DocumentKind.infer(filename: "Invoice 1001 - Lee", fileExtension: "pdf"), .invoice)
        XCTAssertEqual(DocumentKind.infer(filename: "Quote 12", fileExtension: "pdf"), .quote)
        XCTAssertEqual(DocumentKind.infer(filename: "Engagement - Lee 3-4-26", fileExtension: "pdf"), .letter)
        XCTAssertEqual(DocumentKind.infer(filename: "Scan 3-4-26", fileExtension: "pdf"), .upload)
        XCTAssertEqual(DocumentKind.infer(filename: "Photo", fileExtension: "jpg"), .upload)
    }
}

final class FolderMatchTests: XCTestCase {
    private func folder(_ id: String, _ name: String) -> DriveFile { DriveFile(id: id, name: name, mimeType: DriveMime.folder) }

    func testCodes() {
        XCTAssertEqual(FolderMatch.code(of: "03 - Deliverables"), "03")
        XCTAssertEqual(FolderMatch.code(of: "2025"), "2025")
        XCTAssertEqual(FolderMatch.code(of: "Deliverables"), "")
        XCTAssertEqual(FolderMatch.code(of: "2025abc"), "2025")
        XCTAssertEqual(FolderMatch.code(of: "3M Co"), "3")
    }

    func testExactNameWinsThenTheNumber() {
        let children = [folder("A", "02 - Source Docs"), folder("B", "03 - Deliverables"), DriveFile(id: "F", name: "03 - file.pdf", mimeType: "application/pdf")]
        XCTAssertEqual(FolderMatch.match(name: "03 - deliverables", in: children)?.id, "B", "case-insensitive exact")
        XCTAssertEqual(FolderMatch.match(name: "02 - Source Documents (Client Uploads)", in: children)?.id, "A", "same number, different wording")
        XCTAssertNil(FolderMatch.match(name: "04 - Invoices & Engagements", in: children))
        XCTAssertNil(FolderMatch.match(name: "Notes", in: children), "no number and no exact name: nothing to reuse")
    }

    func testFilesAreNeverMatchedAsFolders() {
        let children = [DriveFile(id: "F", name: "2025", mimeType: "application/pdf")]
        XCTAssertNil(FolderMatch.match(name: "2025", in: children))
    }

    func testYearFolderMatchesByExactNumber() {
        let children = [folder("Y24", "2024"), folder("Y25", "2025")]
        XCTAssertEqual(FolderMatch.match(name: "2025", in: children)?.id, "Y25")
        XCTAssertNil(FolderMatch.match(name: "2026", in: children))
    }

    func testClientFolderNames() {
        XCTAssertEqual(ClientFolderName.name(for: " Dana Lee "), "Dana Lee")
        XCTAssertEqual(ClientFolderName.name(for: "A/B: Co"), "A-B- Co")
        XCTAssertEqual(ClientFolderName.name(for: ""), "Client")
    }
}

final class DocumentNamingTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_772_000_000)

    func testDefaultPattern() {
        XCTAssertEqual(
            DocumentNaming.render(pattern: "{year} - {client} - {title}", title: "Engagement Letter", client: "Smith", year: 2025, date: date),
            "2025 - Smith - Engagement Letter"
        )
    }

    func testEmptyPartsLeaveNoDanglingSeparators() {
        XCTAssertEqual(DocumentNaming.render(pattern: "{year} - {client} - {title}", title: "Scan", client: "", year: 2025, date: date), "2025 - Scan")
        XCTAssertEqual(DocumentNaming.render(pattern: "{year} - {client} - {title}", title: "Scan", client: "Lee", year: 0, date: date), "Lee - Scan")
    }

    func testBlankAndTitlelessPatterns() {
        XCTAssertEqual(DocumentNaming.render(pattern: "", title: "W-2", client: "Lee", year: 2025, date: date), "W-2")
        XCTAssertEqual(DocumentNaming.render(pattern: "{client}", title: "W-2", client: "Lee", year: 2025, date: date), "Lee - W-2",
                       "the title is never lost")
    }

    func testDateToken() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = DateComponents(calendar: calendar, year: 2026, month: 3, day: 4, hour: 12).date!
        XCTAssertEqual(DocumentNaming.render(pattern: "{date} {title}", title: "Scan", client: "", year: 2026, date: noon, calendar: calendar), "2026-03-04 Scan")
    }

    func testYearComesFromTheJobElseTheCalendar() {
        XCTAssertEqual(DocumentNaming.year(taxYear: 2025, date: date), 2025)
        XCTAssertEqual(DocumentNaming.year(taxYear: 0, date: date), Calendar.current.component(.year, from: date))
        XCTAssertEqual(DocumentNaming.year(taxYear: nil, date: date), Calendar.current.component(.year, from: date))
    }
}

final class RequestMatcherTests: XCTestCase {
    private func file(_ name: String) -> DriveFile { DriveFile(id: name, name: name, mimeType: "application/pdf") }

    func testPunctuationDoesNotMatter() {
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "W-2", fileName: "2025 W2 - Acme Corp.pdf"))
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "1099-INT", fileName: "1099 INT Chase.pdf"))
        XCTAssertFalse(RequestMatcher.matches(requestTitle: "W-2", fileName: "Bank statement.pdf"))
    }

    func testEveryKeywordMustAppear() {
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "December bank statement", fileName: "Chase bank December.pdf"))
        XCTAssertFalse(RequestMatcher.matches(requestTitle: "December bank statement", fileName: "Chase bank November.pdf"))
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "Property tax bills", fileName: "property-tax-bill-2025.pdf"), "plural stems")
    }

    func testAWrongYearDoesNotMatch() {
        XCTAssertFalse(RequestMatcher.matches(requestTitle: "2025 W-2s", fileName: "2024 W2 Acme.pdf"))
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "2025 W-2s", fileName: "2025 W2 Acme.pdf"))
        XCTAssertTrue(RequestMatcher.matches(requestTitle: "2025 W-2s", fileName: "W2 Acme.pdf"), "a file with no year still counts")
    }

    func testTooVagueARequestNeverMatches() {
        XCTAssertFalse(RequestMatcher.matches(requestTitle: "All documents", fileName: "anything.pdf"))
        XCTAssertFalse(RequestMatcher.matches(requestTitle: "  ", fileName: "anything.pdf"))
    }

    func testSuggestionsSkipFoldersAndUseTheFirstMatch() {
        let id = UUID()
        let files = [
            DriveFile(id: "D", name: "W2 folder", mimeType: DriveMime.folder),
            file("W2 Acme.pdf"), file("W2 Beta.pdf"),
        ]
        let result = RequestMatcher.suggestions(requests: [OpenRequest(id: id, title: "W-2")], files: files)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.fileName, "W2 Acme.pdf")
        XCTAssertEqual(result.first?.requestID, id)
        XCTAssertTrue(RequestMatcher.suggestions(requests: [OpenRequest(id: id, title: "Passport")], files: files).isEmpty)
    }
}
