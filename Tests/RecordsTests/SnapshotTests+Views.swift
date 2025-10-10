import Dependencies
import Records
import RecordsTestSupport
import Testing

// MARK: - VIEW Patterns

extension SnapshotTests {
    @Suite("VIEW Patterns", .serialized)
    struct ViewPatterns {

        @Test("Query simple view")
        func querySimpleView() async throws {
            @Dependency(\.defaultDatabase) var database

            try await database.write { conn in
                // Create the view
                try await CompletedReminder.createTemporaryView(
                    orReplace: true,
                    as: Reminder
                        .where(\.isCompleted)
                        .select { CompletedReminder.Columns(reminderID: $0.id, title: $0.title) }
                ).execute(conn)
            }

            // Query the view
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
        func queryViewWithWhere() async throws {
            @Dependency(\.defaultDatabase) var database

            try await database.write { conn in
                // Create the view
                try await CompletedReminder.createTemporaryView(
                    orReplace: true,
                    as: Reminder
                        .where(\.isCompleted)
                        .select { CompletedReminder.Columns(reminderID: $0.id, title: $0.title) }
                ).execute(conn)
            }

            // Query the view with WHERE clause
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
        func queryViewFilteringByList() async throws {
            @Dependency(\.defaultDatabase) var database

            try await database.write { conn in
                // Create the view
                try await ReminderWithList.createTemporaryView(
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
                ).execute(conn)
            }

            // Query the view with filtering
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
        func findByPrimaryKey() async throws {
            @Dependency(\.defaultDatabase) var database

            try await database.write { conn in
                // Create the view
                try await ReminderWithList.createTemporaryView(
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
                ).execute(conn)
            }

            // Find by primary key
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
        func queryViewWithOrderAndLimit() async throws {
            @Dependency(\.defaultDatabase) var database

            try await database.write { conn in
                // Create the view
                try await ReminderWithList.createTemporaryView(
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
                ).execute(conn)
            }

            // Query with ordering and limit
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

        @Test("Parameterized queries in views are prevented", .bug("https://www.postgresql.org/docs/current/sql-createview.html"))
        func parameterizedQueriesInViewsFail() async throws {
            @Dependency(\.defaultDatabase) var database

            await #expect(throws: ParameterizedViewError.self) {
                try await database.write { conn in
                    // This should fail because .limit(1) creates a parameterized query
                    try await TestView.createTemporaryView(
                        as: Reminder
                            .where(\.isCompleted)
                            .limit(1)
                            .select { TestView.Columns(id: $0.id, title: $0.title) }
                    ).execute(conn)
                }
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

@Table
private struct TestView {
    let id: Reminder.ID
    let title: String
}
