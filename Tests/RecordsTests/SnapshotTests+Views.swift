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

                // Query the view within the same connection
                let query = CompletedReminder.limit(2).select { $0.title }
                let results = try await conn.fetchAll(query)

                #expect(results.count == 1)
                #expect(results[0] == "Finish report")

                // Clean up: Drop the view
                try await CompletedReminder.createTemporaryView(
                    as: Reminder.all.select { CompletedReminder.Columns(reminderID: $0.id, title: $0.title) }
                ).drop(ifExists: true).execute(conn)
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

                // Query the view with WHERE clause
                let query = CompletedReminder
                    .where { $0.title.like("%report%") }
                    .select { $0.title }
                let results = try await conn.fetchAll(query)

                #expect(results.count == 1)
                #expect(results[0] == "Finish report")

                // Clean up
                try await CompletedReminder.createTemporaryView(
                    as: Reminder.all.select { CompletedReminder.Columns(reminderID: $0.id, title: $0.title) }
                ).drop(ifExists: true).execute(conn)
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

                // Query the view with filtering
                let query = ReminderWithList
                    .where { $0.remindersListTitle == "Work" }
                    .order(by: { $0.reminderTitle })
                    .select { $0.reminderTitle }
                let results = try await conn.fetchAll(query)

                #expect(results.count == 3)
                #expect(results[0] == "Finish report")
                #expect(results[1] == "Review PR")
                #expect(results[2] == "Team meeting")

                // Clean up
                try await ReminderWithList.createTemporaryView(
                    as: Reminder.all.select {
                        ReminderWithList.Columns(
                            reminderID: $0.id,
                            reminderTitle: $0.title,
                            remindersListTitle: $0.title
                        )
                    }
                ).drop(ifExists: true).execute(conn)
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

                // Find by primary key
                let query = ReminderWithList.find(1).select { ($0.reminderTitle, $0.remindersListTitle) }
                let results = try await conn.fetchAll(query)

                #expect(results.count == 1)
                #expect(results[0].0 == "Groceries")
                #expect(results[0].1 == "Home")

                // Clean up
                try await ReminderWithList.createTemporaryView(
                    as: Reminder.all.select {
                        ReminderWithList.Columns(
                            reminderID: $0.id,
                            reminderTitle: $0.title,
                            remindersListTitle: $0.title
                        )
                    }
                ).drop(ifExists: true).execute(conn)
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

                // Query with ordering and limit
                let query = ReminderWithList
                    .order(by: { ($0.remindersListTitle, $0.reminderTitle) })
                    .limit(3)
                    .select { ($0.reminderTitle, $0.remindersListTitle) }
                let results = try await conn.fetchAll(query)

                #expect(results.count == 3)
                #expect(results[0].0 == "Groceries")
                #expect(results[0].1 == "Home")
                #expect(results[1].0 == "Haircut")
                #expect(results[1].1 == "Home")
                #expect(results[2].0 == "Vet appointment")
                #expect(results[2].1 == "Home")

                // Clean up
                try await ReminderWithList.createTemporaryView(
                    as: Reminder.all.select {
                        ReminderWithList.Columns(
                            reminderID: $0.id,
                            reminderTitle: $0.title,
                            remindersListTitle: $0.title
                        )
                    }
                ).drop(ifExists: true).execute(conn)
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
