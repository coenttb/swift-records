import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "UPDATE Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct ExecutionUpdateTests {
    @Dependency(\.defaultDatabase) var db

    @Test("UPDATE with WHERE and RETURNING")
    func updateWithWhereAndReturning() async throws {
        let results = try await db.write { db in
            try await Reminder
                .where { $0.priority == Priority.high }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.priority == Priority.high)
        #expect(results.first?.isCompleted == true)
    }

    @Test("UPDATE with NULL values")
    func updateWithNull() async throws {
        // Update to set assignedUserID to nil
        try await db.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.assignedUserID = nil }
                .execute(db)
        }

        // Verify with SELECT
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }

        #expect(reminder?.id == 1)
        #expect(reminder?.assignedUserID == nil)
    }

    @Test("UPDATE multiple columns")
    func updateMultipleColumns() async throws {
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == 2 }
                .update { reminder in
                    reminder.isCompleted = true
                    reminder.notes = "Completed"
                }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.isCompleted == true)
        #expect(results.first?.notes == "Completed")
    }

    @Test("UPDATE with no matches returns empty")
    func updateNoMatches() async throws {
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == 999 }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 0)
    }

    @Test("UPDATE with WHERE on foreign key")
    func updateWithForeignKey() async throws {
        // Update reminders in a specific list
        let results = try await db.write { db in
            try await Reminder
                .where { $0.remindersListID == 1 }
                .update { $0.isFlagged = true }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 3) // Home list has 3 reminders
        #expect(results.allSatisfy { $0.isFlagged == true })
    }

    @Test("UPDATE all rows")
    func updateAllRows() async throws {
        let results = try await db.write { db in
            try await Reminder
                .update { $0.isFlagged = false }
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.isFlagged == false })
    }

    @Test("UPDATE with boolean field")
    func updateBoolean() async throws {
        // Get original state
        let original = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }

        #expect(original?.isCompleted == false)

        // Update
        let updated = try await db.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.isCompleted = true }
                .returning(\.self)
                .fetchOne(db)
        }

        #expect(updated?.isCompleted == true)
    }

    @Test("UPDATE with text concatenation")
    func updateTextConcat() async throws {
        // Note: SQL string concatenation using + operator (translates to ||)
        try await db.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.notes = $0.notes + " - Updated" }
                .execute(db)
        }

        // Verify with SELECT
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }

        #expect(reminder?.id == 1)
        #expect(reminder?.notes == "Milk, Eggs, Apples - Updated")
    }
}
