import XCTest
import SwiftData
@testable import CPAManager

final class DriveFilingLogicTests: XCTestCase {
    func testDestinationPrefersTheJobFolderThenTheClientFolder() {
        XCTAssertEqual(DriveFilingPlan.destinationFolder(projectFolder: "JOB1", clientFolder: "CLIENT1"), "JOB1")
        XCTAssertEqual(DriveFilingPlan.destinationFolder(projectFolder: "", clientFolder: "CLIENT1"), "CLIENT1")
        XCTAssertNil(DriveFilingPlan.destinationFolder(projectFolder: "", clientFolder: ""))
    }

    func testDestinationRefusesUnsafeIDsAndTheDriveRoot() {
        XCTAssertNil(DriveFilingPlan.destinationFolder(projectFolder: "x' or 'a", clientFolder: ""))
        XCTAssertNil(DriveFilingPlan.destinationFolder(projectFolder: "root", clientFolder: ""))
        XCTAssertEqual(DriveFilingPlan.destinationFolder(projectFolder: "bad id", clientFolder: "OK_1"), "OK_1",
                       "an unusable job folder falls back to the client's")
    }

    func testMimeTypes() {
        XCTAssertEqual(DriveFilingPlan.mimeType(forExtension: "PDF"), "application/pdf")
        XCTAssertEqual(DriveFilingPlan.mimeType(forExtension: ".jpeg"), "image/jpeg")
        XCTAssertEqual(DriveFilingPlan.mimeType(forExtension: "heic"), "image/heic")
        XCTAssertEqual(DriveFilingPlan.mimeType(forExtension: "xyz"), "application/octet-stream")
    }

    func testDriveNamesHaveOneExtensionAndNoSlashes() {
        XCTAssertEqual(DriveFilingPlan.driveName(filename: "Engagement 3/4/26", fileExtension: "pdf"), "Engagement 3-4-26.pdf")
        XCTAssertEqual(DriveFilingPlan.driveName(filename: "W-2.PDF", fileExtension: "pdf"), "W-2.PDF")
        XCTAssertEqual(DriveFilingPlan.driveName(filename: "  ", fileExtension: ".jpg"), "Document.jpg")
        XCTAssertEqual(DriveFilingPlan.driveName(filename: "notes", fileExtension: ""), "notes")
    }

    func testOnlyLocalFilesCanMove() {
        XCTAssertTrue(DriveFilingPlan.canMove(hasData: true, isDriveLink: false))
        XCTAssertFalse(DriveFilingPlan.canMove(hasData: false, isDriveLink: false))
        XCTAssertFalse(DriveFilingPlan.canMove(hasData: true, isDriveLink: true), "never upload a file that's already a Drive link")
    }

    func testStatusesMapToReasons() {
        XCTAssertEqual(DriveFilingPlan.reason(forHTTPStatus: 403), .needsReconnect)
        XCTAssertEqual(DriveFilingPlan.reason(forHTTPStatus: 401), .needsReconnect)
        XCTAssertEqual(DriveFilingPlan.reason(forHTTPStatus: 500), .failed)
    }

    func testNoticesNameTheFixAndTheClient() {
        XCTAssertTrue(DriveFilingPlan.notice(for: .noFolder, clientName: "Dana Lee").contains("Dana Lee"))
        XCTAssertTrue(DriveFilingPlan.notice(for: .noFolder, clientName: " ").contains("this client"))
        XCTAssertTrue(DriveFilingPlan.notice(for: .needsReconnect, clientName: "").contains("Reconnect"))
        XCTAssertTrue(DriveFilingPlan.notice(for: .notConnected, clientName: "").contains("Connect Google"))
        for reason in [DriveFilingReason.turnedOff, .notConnected, .noFolder, .needsReconnect, .failed] {
            XCTAssertTrue(DriveFilingPlan.notice(for: reason, clientName: "").hasPrefix("Saved in the app"))
        }
    }

    func testMultipartBodyHasMetadataThenBytes() throws {
        let payload = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
        let body = DriveUpload.multipartBody(name: "a.pdf", mimeType: "application/pdf", parentID: "FOLDER1", data: payload, boundary: "BND")
        XCTAssertEqual(DriveUpload.contentType(boundary: "BND"), "multipart/related; boundary=BND")

        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("--BND\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"))
        XCTAssertTrue(text.contains("\"parents\":[\"FOLDER1\"]"))
        XCTAssertTrue(text.contains("\"name\":\"a.pdf\""))
        XCTAssertTrue(text.contains("\r\n--BND\r\nContent-Type: application/pdf\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--BND--\r\n"))
        XCTAssertNotNil(body.range(of: payload), "the raw bytes are in the body unmodified")
    }

    func testMultipartBodyDropsAnUnsafeParent() {
        let body = DriveUpload.multipartBody(name: "a", mimeType: "image/png", parentID: "bad/../id", data: Data([1]), boundary: "B")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("parents"))
    }
}

@MainActor
final class DriveFilingServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: Persistence.schema, configurations: config))
    }

    func testAddKeepsTheFileLocallyWhenGoogleIsNotConnected() async throws {
        let auth = GoogleAuthService()
        try XCTSkipIf(auth.isConnected, "needs a device with no Google connection")
        let context = try makeContext()
        let client = Client(name: "Dana Lee")
        client.driveFolderID = "FOLDER1"
        context.insert(client)

        let result = await DriveFiling.add(
            data: Data([1, 2, 3]), filename: "Scan", fileExtension: "pdf",
            client: client, project: nil, auth: auth, context: context
        )
        XCTAssertEqual(result.outcome.reason, .notConnected)
        XCTAssertEqual(result.document.data, Data([1, 2, 3]), "nothing is lost when Drive can't take the file")
        XCTAssertFalse(result.document.isDriveLink)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Document>()).count, 1)
    }

    func testMoveLeavesALinkedDocumentAlone() async throws {
        let context = try makeContext()
        let document = Document(filename: "Linked", fileExtension: "pdf", data: Data())
        document.driveFileID = "F1"
        context.insert(document)
        let outcome = await DriveFiling.move(document, auth: GoogleAuthService(), context: context)
        XCTAssertTrue(outcome.inDrive, "already in Drive counts as done")
        XCTAssertEqual(document.driveFileID, "F1")
    }
}
