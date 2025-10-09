import Dependencies
import DependenciesTestSupport
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "Transaction Management",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct TransactionTests {
    @Dependency(\.defaultDatabase) var database

    @Test("withTransaction commits on success")
    func testWithTransaction() async throws {
        // Execute transaction
        try await database.withTransaction { db in
            try await RemindersList.insert {
                RemindersList.Draft(color: 0xFF0000, title: "Transaction List", position: 2)
            }.execute(db)

            try await Reminder.insert {
                Reminder.Draft(
                    notes: "Test transaction",
                    remindersListID: 3, // New list we just created
                    title: "Transaction Reminder"
                )
            }.execute(db)
        }

        // Verify data was committed (2 from sample + 1 new = 3)
        let listCount = try await database.read { db in
            try await RemindersList.fetchCount(db)
        }

        let reminderCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        #expect(listCount == 3)
        #expect(reminderCount == 7) // 6 from sample + 1 new
    }

    @Test("Transaction rolls back on error")
    func testTransactionRollback() async throws {
        // Count initial state (6 reminders from sample data)
        let initialReminderCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        // Attempt transaction that will fail
        do {
            try await database.withTransaction { db in
                // This should succeed
                try await Reminder.insert {
                    Reminder.Draft(
                        notes: "Should not persist",
                        remindersListID: 1,
                        title: "Will Rollback"
                    )
                }.execute(db)

                // Force an error
                struct TestError: Error {}
                throw TestError()
            }

            Issue.record("Transaction should have failed")
        } catch {
            // Expected error
        }

        // Verify rollback (should still be 6)
        let finalReminderCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        #expect(finalReminderCount == initialReminderCount)
    }

    @Test("Transaction isolation levels")
    func testTransactionIsolationLevels() async throws {
        // Test different isolation levels
        let isolationLevels: [TransactionIsolationLevel] = [
            .readCommitted,
            .repeatableRead,
            .serializable
        ]

        for level in isolationLevels {
            try await database.withTransaction(isolation: level) { db in
                try await Reminder.insert {
                    Reminder.Draft(
                        notes: "Testing isolation level \(level)",
                        remindersListID: 1,
                        title: "Isolation \(level)"
                    )
                }.execute(db)
            }
        }

        // Verify all were inserted (6 from sample + 3 new = 9)
        let reminders = try await database.read { db in
            try await Reminder.fetchAll(db)
        }

        #expect(reminders.count == 9)
    }

    @Test("withRollback always rolls back")
    func testWithRollback() async throws {
        // Count initial state (6 from sample data)
        let initialCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        // Execute with rollback
        try await database.withRollback { db in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "Should not persist",
                    remindersListID: 1,
                    title: "Will Rollback"
                )
            }.execute(db)

            // Verify insert worked within transaction
            let count = try await Reminder.fetchCount(db)
            #expect(count == initialCount + 1)
        }

        // Verify rollback occurred (should still be 6)
        let finalCount = try await database.read { db in
            try await Reminder.fetchCount(db)
        }

        #expect(finalCount == initialCount)
    }

    @Test(
        "withSavepoint allows partial rollback",
        .disabled()
    )
    func testWithSavepoint() async throws {
        try await database.withTransaction { db in
            // Insert first reminder
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "",
                    remindersListID: 1,
                    title: "Before Savepoint"
                )
            }.execute(db)

            // Try savepoint that will rollback
            do {
                try await database.withSavepoint("test_savepoint") { spDb in
                    try await Reminder.insert {
                        Reminder.Draft(
                            notes: "",
                            remindersListID: 1,
                            title: "In Savepoint"
                        )
                    }.execute(spDb)

                    // Force rollback of savepoint
                    struct SavepointError: Error {}
                    throw SavepointError()
                }
            } catch {
                // Expected - savepoint rolled back
            }

            // Insert after savepoint
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "",
                    remindersListID: 1,
                    title: "After Savepoint"
                )
            }.execute(db)
        }

        // Verify only reminders outside savepoint were committed
        let reminders = try await database.read { db in
            try await Reminder.fetchAll(db)
        }

        let titles = reminders.map(\.title)
        #expect(titles.contains("Before Savepoint"))
        #expect(titles.contains("After Savepoint"))
        #expect(!titles.contains("In Savepoint"))
    }

    @Test(
        "Nested transactions behavior",
        .disabled()
    )
    func testNestedTransactions() async throws {
        // Test nested transaction behavior
        try await database.withTransaction { db1 in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "",
                    remindersListID: 1,
                    title: "Outer Transaction"
                )
            }.execute(db1)

            // Nested transaction (actually a savepoint in PostgreSQL)
            try await database.withTransaction { db2 in
                try await Reminder.insert {
                    Reminder.Draft(
                        notes: "",
                        remindersListID: 1,
                        title: "Inner Transaction"
                    )
                }.execute(db2)
            }
        }

        // Both should be committed
        let reminders = try await database.read { db in
            try await Reminder.fetchAll(db)
        }

        let titles = reminders.map(\.title)
        #expect(titles.contains("Outer Transaction"))
        #expect(titles.contains("Inner Transaction"))
    }
}
