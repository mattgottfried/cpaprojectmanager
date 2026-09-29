import XCTest
@testable import CPAManager

final class AppRouterTests: XCTestCase {
    func testWidgetLinksRoute() {
        let router = AppRouter()
        XCTAssertTrue(router.handle(url: URL(string: "cpamanager://capture")!))
        XCTAssertEqual(router.section, .today)
        XCTAssertEqual(router.pendingFocus, .newTask)

        XCTAssertTrue(router.handle(url: URL(string: "cpamanager://inbox")!))
        XCTAssertEqual(router.section, .inbox)
        XCTAssertNil(router.pendingFocus, "navigating without a focus request clears the old one")

        XCTAssertTrue(router.handle(url: URL(string: "cpamanager://review")!))
        XCTAssertEqual(router.section, .review)
    }

    func testUnknownOrForeignURLsAreIgnored() {
        let router = AppRouter()
        router.go(to: .clients)
        XCTAssertFalse(router.handle(url: URL(string: "cpamanager://oauth-callback?code=1")!))
        XCTAssertFalse(router.handle(url: URL(string: "https://example.com/today")!))
        XCTAssertEqual(router.section, .clients)
    }

    func testEverySectionHasTitleAndIcon() {
        for section in AppSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
        }
        XCTAssertEqual(Set(AppSection.daily + AppSection.practice + [.settings]), Set(AppSection.allCases))
    }
}

final class WidgetSnapshotTests: XCTestCase {
    private func item(overdue: Bool, dueToday: Bool) -> DashboardSnapshot.Item {
        let cal = Calendar.current
        let day = overdue
            ? cal.date(byAdding: .day, value: -2, to: .now)!
            : (dueToday ? Date.now : cal.date(byAdding: .day, value: 3, to: .now)!)
        return .init(id: UUID(), title: "t", subtitle: "", dueDate: day, isOverdue: overdue, isTask: true)
    }

    func testRemovingItemUpdatesCountsAndLists() {
        let late = item(overdue: true, dueToday: false)
        let today = item(overdue: false, dueToday: true)
        let snapshot = DashboardSnapshot(
            generatedAt: .now, dueTodayCount: 1, overdueCount: 1, openProjectCount: 2,
            upcoming: [late, today], todayItems: [late, today], inboxCount: 0
        )

        let afterLate = snapshot.removingItem(id: late.id)
        XCTAssertEqual(afterLate.overdueCount, 0)
        XCTAssertEqual(afterLate.dueTodayCount, 1)
        XCTAssertEqual(afterLate.todayItems?.map { $0.id }, [today.id])
        XCTAssertEqual(afterLate.upcoming.map { $0.id }, [today.id])

        let afterToday = snapshot.removingItem(id: today.id)
        XCTAssertEqual(afterToday.dueTodayCount, 0)
        XCTAssertEqual(afterToday.overdueCount, 1)
    }

    func testRemovingUnknownItemChangesNothing() {
        let snapshot = DashboardSnapshot.empty
        XCTAssertEqual(snapshot.removingItem(id: UUID()), snapshot)
    }

    func testOlderSnapshotsWithoutNewFieldsStillDecode() throws {
        let json = """
        {"generatedAt": 0, "dueTodayCount": 2, "overdueCount": 1, "openProjectCount": 3, "upcoming": []}
        """
        let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.dueTodayCount, 2)
        XCTAssertNil(decoded.todayItems)
        XCTAssertNil(decoded.inboxCount)
    }

    func testInboxSourceMapsToInteractionKind() {
        XCTAssertEqual(InboxService.interactionKind(for: .text), .text)
        XCTAssertEqual(InboxService.interactionKind(for: .email), .email)
        XCTAssertEqual(InboxService.interactionKind(for: .note), .note)
        XCTAssertEqual(InboxService.interactionKind(for: .manual), .note)
    }
}
