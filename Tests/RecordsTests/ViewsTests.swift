import Dependencies
import Foundation
import InlineSnapshotTesting
import Records
import RecordsTestSupport
import StructuredQueriesPostgres
import Testing

@Suite(
    "Database Views Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderDataAndViews()
    }
)
struct ViewsTests {
    @Dependency(\.defaultDatabase) var database

    @Test("Query simple view")
    func querySimpleView() async {
        await assertQuery(
            CompletedReminder.limit(2).select { $0.title }
        ) {
            """
            SELECT "completedReminders"."title"
            FROM "completedReminders"
            LIMIT 2
            """
        } results: {
            """
            ┌─────────────────┐
            │ "Finish report" │
            └─────────────────┘
            """
        }
    }

    @Test("Query view with WHERE clause")
    func queryViewWithWhere() async {
        await assertQuery(
            CompletedReminder
                .where { $0.title.like("%report%") }
                .select { $0.title }
        ) {
            """
            SELECT "completedReminders"."title"
            FROM "completedReminders"
            WHERE ("completedReminders"."title" LIKE '%report%')
            """
        } results: {
            """
            ┌─────────────────┐
            │ "Finish report" │
            └─────────────────┘
            """
        }
    }

    @Test("Query view filtering by list")
    func queryViewFilteringByList() async {
        await assertQuery(
            ReminderWithList
                .where { $0.remindersListTitle == "Work" }
                .order(by: { $0.reminderTitle })
                .select { $0.reminderTitle }
        ) {
            """
            SELECT "reminderWithLists"."reminderTitle"
            FROM "reminderWithLists"
            WHERE ("reminderWithLists"."remindersListTitle" = 'Work')
            ORDER BY "reminderWithLists"."reminderTitle"
            """
        } results: {
            """
            ┌─────────────────┐
            │ "Finish report" │
            │ "Review PR"     │
            │ "Team meeting"  │
            └─────────────────┘
            """
        }
    }

    @Test("Find record by primary key in view")
    func findByPrimaryKey() async {
        await assertQuery(
            ReminderWithList.find(1).select { ($0.reminderTitle, $0.remindersListTitle) }
        ) {
            """
            SELECT "reminderWithLists"."reminderTitle", "reminderWithLists"."remindersListTitle"
            FROM "reminderWithLists"
            WHERE ("reminderWithLists"."reminderID" IN (1))
            """
        } results: {
            """
            ┌─────────────┬────────┐
            │ "Groceries" │ "Home" │
            └─────────────┴────────┘
            """
        }
    }

    @Test("Query view with ordering and limit")
    func queryViewWithOrderAndLimit() async {
        await assertQuery(
            ReminderWithList
                .order(by: { ($0.remindersListTitle, $0.reminderTitle) })
                .limit(3)
                .select { ($0.reminderTitle, $0.remindersListTitle) }
        ) {
            """
            SELECT "reminderWithLists"."reminderTitle", "reminderWithLists"."remindersListTitle"
            FROM "reminderWithLists"
            ORDER BY "reminderWithLists"."remindersListTitle", "reminderWithLists"."reminderTitle"
            LIMIT 3
            """
        } results: {
            """
            ┌───────────────────┬────────┐
            │ "Groceries"       │ "Home" │
            │ "Haircut"         │ "Home" │
            │ "Vet appointment" │ "Home" │
            └───────────────────┴────────┘
            """
        }
    }

    @Test("Drop and recreate view with OR REPLACE")
    func dropAndRecreateView() async throws {
        @Dependency(\.defaultDatabase) var database

        try await database.write { conn in
            // Create initial view - flagged reminders
            try await TestView.createTemporaryView(
                as: Reminder
                    .where(\.isFlagged)
                    .select { TestView.Columns(id: $0.id, title: $0.title) }
            ).execute(conn)

            // Query the view to confirm it exists
            let initialResults = try await TestView.all.fetchAll(conn)
            #expect(initialResults.count == 2) // "Haircut" and "Team meeting" are flagged

            // Replace the view with different query using OR REPLACE (completed reminders)
            try await TestView.createTemporaryView(
                orReplace: true,
                as: Reminder
                    .where(\.isCompleted)
                    .select { TestView.Columns(id: $0.id, title: $0.title) }
            ).execute(conn)

            // Query the replaced view - should now show completed reminders
            let replacedResults = try await TestView.all.fetchAll(conn)
            #expect(replacedResults.count == 1)
            #expect(replacedResults[0].title == "Finish report")

            // Drop the view with IF EXISTS
            try await TestView.createTemporaryView(
                as: Reminder.all.select { TestView.Columns(id: $0.id, title: $0.title) }
            ).drop(ifExists: true).execute(conn)

            // Verify view is dropped by expecting an error when querying
            do {
                _ = try await TestView.all.fetchAll(conn)
                Issue.record("Expected error when querying dropped view")
            } catch {
                // Expected - view should not exist
            }
        }
    }
}

// MARK: - View Table Definitions

@Table
private struct CompletedReminder {
    let reminderID: Reminder.ID
    let title: String
}

@Table
private struct ReminderWithList {
    @Column(primaryKey: true)
    let reminderID: Reminder.ID
    let reminderTitle: String
    let remindersListTitle: String
}

// MARK: - Test Database Setup with Views

fileprivate extension Database.TestDatabaseSetupMode {
    /// Reminder schema with sample data AND temporary views pre-installed
    static let withReminderDataAndViews = Database.TestDatabaseSetupMode { db in
        // First create the base schema and data
        try await db.createReminderSchema()
        try await db.insertReminderSampleData()

        // Then install the temporary views
        try await db.installReminderViews()
    }
}

// MARK: - Helper Extensions

fileprivate extension Database.Writer {
    /// Installs temporary views for reminder tests
    func installReminderViews() async throws {
        try await self.write { conn in
            // Create CompletedReminder view (with OR REPLACE to handle re-runs)
            let completedView = CompletedReminder.createTemporaryView(
                orReplace: true,
                as: Reminder
                    .where(\.isCompleted)
                    .select { CompletedReminder.Columns(reminderID: $0.id, title: $0.title) }
            )
            let (completedSQL, _) = completedView.query.prepare { "$\($0)" }
            try await conn.execute(completedSQL)

            // Create ReminderWithList view (with OR REPLACE to handle re-runs)
            let reminderListView = ReminderWithList.createTemporaryView(
                orReplace: true,
                as: Reminder
                    .join(RemindersList.all) { $0.remindersListID.eq($1.id) }
                    .select {
                        ReminderWithList.Columns(
                            reminderID: $0.id,
                            reminderTitle: $0.title,
                            remindersListTitle: $1.title
                        )
                    }
            )
            let (reminderListSQL, _) = reminderListView.query.prepare { "$\($0)" }
            try await conn.execute(reminderListSQL)
        }
    }
}

extension Database.TestDatabase {
    /// Creates a test database with Reminder schema, sample data, and views
    static func withReminderDataAndViews() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withReminderDataAndViews)
    }
}

// Create a test view
@Table
private struct TestView {
    let id: Reminder.ID
    let title: String
}
