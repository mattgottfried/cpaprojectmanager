import XCTest
import SwiftData
@testable import CPAManager

final class DriveLogicTests: XCTestCase {
    func testDecodesAListResponseWithSizesAndFractionalTimes() throws {
        let json = #"""
        {"nextPageToken":"tok","files":[
          {"id":"F1","name":"Smith 2025","mimeType":"application/vnd.google-apps.folder","modifiedTime":"2026-03-01T10:30:45.123Z"},
          {"id":"F2","name":"W-2.pdf","mimeType":"application/pdf","modifiedTime":"2026-03-02T08:00:00Z","size":"12345","webViewLink":"https://drive.google.com/file/d/F2/view"},
          {"id":"F3","mimeType":"image/png"}
        ]}
        """#
        let response = try XCTUnwrap(DriveParsing.decode(Data(json.utf8)))
        XCTAssertEqual(response.nextPageToken, "tok")
        let files = try XCTUnwrap(response.files)
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files[0].isFolder)
        XCTAssertNotNil(files[0].modifiedTime, "fractional seconds parse")
        XCTAssertNotNil(files[1].modifiedTime, "plain seconds parse")
        XCTAssertEqual(files[1].size, 12_345)
        XCTAssertEqual(files[2].name, "Untitled", "a missing name gets a placeholder")
        XCTAssertNil(DriveParsing.decode(Data("nope".utf8)))
    }

    func testQueriesEscapeAndRefuseUnsafeIDs() {
        XCTAssertEqual(DriveQuery.children(of: "abc_DEF-123"), "'abc_DEF-123' in parents and trashed = false")
        XCTAssertNotNil(DriveQuery.children(of: "root"))
        XCTAssertNil(DriveQuery.children(of: "x' or name contains 'a"), "an id can't rewrite the query")
        XCTAssertNil(DriveQuery.children(of: ""))
        XCTAssertEqual(DriveQuery.search("O'Brien \\ Co"), "name contains 'O\\'Brien \\\\ Co' and trashed = false")
        XCTAssertNil(DriveQuery.search("   "))
        XCTAssertEqual(DriveQuery.foldersOnly("a"), "a and mimeType = 'application/vnd.google-apps.folder'")
    }

    func testLinks() {
        let withLink = DriveFile(id: "F2", name: "a.pdf", mimeType: "application/pdf", webViewLink: "https://drive.google.com/file/d/F2/view")
        XCTAssertEqual(DriveLinks.fileURL(withLink)?.absoluteString, "https://drive.google.com/file/d/F2/view")
        let bare = DriveFile(id: "ABC123", name: "b", mimeType: "image/png")
        XCTAssertEqual(DriveLinks.fileURL(bare)?.absoluteString, "https://drive.google.com/file/d/ABC123/view")
        XCTAssertNil(DriveLinks.fileURL(DriveFile(id: "bad id", name: "c", mimeType: "x")))
        XCTAssertNil(DriveLinks.fileURL(DriveFile(id: "ok", name: "d", mimeType: "x", webViewLink: "javascript:alert(1)")).flatMap { $0.scheme == "https" ? nil : $0 },
                     "only https links are opened")
        XCTAssertEqual(DriveLinks.folderURL(id: "FOLDER1").absoluteString, "https://drive.google.com/drive/folders/FOLDER1")
        XCTAssertEqual(DriveLinks.folderURL(id: "root"), DriveLinks.myDrive)
        XCTAssertEqual(DriveLinks.folderURL(id: "bad/../id"), DriveLinks.myDrive)
    }

    func testKindsExtensionsAndTitles() {
        XCTAssertEqual(DriveFileKind.symbol(for: DriveFile(id: "1", name: "f", mimeType: DriveMime.folder)), "folder.fill")
        XCTAssertEqual(DriveFileKind.symbol(for: DriveFile(id: "1", name: "f", mimeType: "image/jpeg")), "photo.fill")
        XCTAssertEqual(DriveFileKind.fileExtension(for: DriveFile(id: "1", name: "Return.PDF", mimeType: "application/pdf")), "pdf")
        XCTAssertEqual(DriveFileKind.fileExtension(for: DriveFile(id: "1", name: "Budget", mimeType: DriveMime.spreadsheet)), "gsheet")
        XCTAssertEqual(DriveFileKind.title(for: DriveFile(id: "1", name: "Return.PDF", mimeType: "application/pdf")), "Return")
        XCTAssertEqual(DriveFileKind.title(for: DriveFile(id: "1", name: "Notes", mimeType: DriveMime.document)), "Notes")
    }

    func testFoldersSortFirstThenByName() {
        let sorted = DriveFileKind.sorted([
            DriveFile(id: "1", name: "b.pdf", mimeType: "application/pdf"),
            DriveFile(id: "2", name: "Zed", mimeType: DriveMime.folder),
            DriveFile(id: "3", name: "a.pdf", mimeType: "application/pdf"),
            DriveFile(id: "4", name: "alpha", mimeType: DriveMime.folder),
        ])
        XCTAssertEqual(sorted.map(\.name), ["alpha", "Zed", "a.pdf", "b.pdf"])
    }

    func testPathNavigation() {
        var path = DrivePath()
        XCTAssertEqual(path.current, DrivePath.root)
        XCTAssertFalse(path.canGoUp)
        let clients = DriveFile(id: "C", name: "Clients", mimeType: DriveMime.folder)
        let smith = DriveFile(id: "S", name: "Smith", mimeType: DriveMime.folder)
        path.open(clients); path.open(smith)
        XCTAssertEqual(path.crumbs.map(\.name), ["My Drive", "Clients", "Smith"])
        path.open(DriveFile(id: "F", name: "file.pdf", mimeType: "application/pdf"))
        XCTAssertEqual(path.crumbs.count, 3, "files can't be opened as folders")
        path.up()
        XCTAssertEqual(path.current.name, "Clients")
        path.open(smith)
        path.jump(to: DrivePath.root)
        XCTAssertEqual(path.crumbs, [DrivePath.root])

        let started = DrivePath(startingIn: DrivePath.Crumb(id: "S", name: "Smith"))
        XCTAssertEqual(started.crumbs.map(\.name), ["My Drive", "Smith"])
        XCTAssertEqual(DrivePath(startingIn: DrivePath.root).crumbs.count, 1)
    }

    func testLinkPlanSkipsFoldersAndDuplicates() {
        let files = [
            DriveFile(id: "A", name: "a", mimeType: "application/pdf"),
            DriveFile(id: "A", name: "a again", mimeType: "application/pdf"),
            DriveFile(id: "B", name: "b", mimeType: "application/pdf"),
            DriveFile(id: "D", name: "dir", mimeType: DriveMime.folder),
        ]
        XCTAssertEqual(DriveLinkPlan.newFiles(files, alreadyLinked: ["B"]).map(\.id), ["A"])
    }

    func testErrorWording() {
        XCTAssertTrue(DriveErrors.message(status: 403, body: "Request had insufficient authentication scopes.").contains("Reconnect"))
        XCTAssertTrue(DriveErrors.message(status: 403, body: "accessNotConfigured: Drive API has not been used").contains("isn't turned on"))
        XCTAssertTrue(DriveErrors.message(status: 401, body: "").contains("expired"))
        XCTAssertTrue(DriveErrors.message(status: 404, body: "").contains("isn't available"))
        XCTAssertEqual(DriveErrors.message(status: 500, body: ""), "Google Drive error (500).")
    }

    func testOAuthRequestsDriveReadOnly() {
        XCTAssertTrue(GoogleOAuth.scopes.contains("https://www.googleapis.com/auth/drive.readonly"))
        XCTAssertFalse(GoogleOAuth.scopes.contains("https://www.googleapis.com/auth/drive"), "never the read-write scope")
    }
}

@MainActor
final class DriveLinkerTests: XCTestCase {
    func testLinkingCreatesDocumentsOnceAndSurvivesBackup() throws {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = try ModelContainer(for: Persistence.schema, configurations: config).mainContext
        let client = Client(name: "Dana")
        context.insert(client)
        let files = [
            DriveFile(id: "F1", name: "W-2.pdf", mimeType: "application/pdf", webViewLink: "https://drive.google.com/file/d/F1/view"),
            DriveFile(id: "F2", name: "Folder", mimeType: DriveMime.folder),
        ]
        XCTAssertEqual(DriveLinker.link(files, client: client, project: nil, context: context), 1)
        XCTAssertEqual(DriveLinker.link(files, client: client, project: nil, context: context), 0, "already linked")

        let doc = try XCTUnwrap(try context.fetch(FetchDescriptor<Document>()).first)
        XCTAssertTrue(doc.isDriveLink)
        XCTAssertEqual(doc.filename, "W-2")
        XCTAssertEqual(doc.fileExtension, "pdf")
        XCTAssertTrue(doc.data.isEmpty)

        client.driveFolderID = "FOLDER"; client.driveFolderName = "Dana Lee"
        let file = BackupService.export(context: context)
        XCTAssertEqual(file.documents.first?.driveFileID, "F1")
        XCTAssertEqual(file.clients.first?.driveFolderName, "Dana Lee")

        let target = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)).mainContext
        BackupService.restore(file, into: target)
        XCTAssertEqual(try target.fetch(FetchDescriptor<Document>()).first?.driveURL, "https://drive.google.com/file/d/F1/view")
        XCTAssertEqual(try target.fetch(FetchDescriptor<Client>()).first?.driveFolderID, "FOLDER")
    }
}
