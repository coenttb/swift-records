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
                .returning { $0.priority }
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first == Priority.high)
    }

    @Test("UPDATE with NULL values")
    func updateWithNull() async throws {
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.assignedUserID = .null }
                .returning { ($0.id, $0.assignedUserID) }
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.0 == 1)
        #expect(results.first?.1 == nil)
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
                .returning { ($0.id, $0.isCompleted, $0.notes) }
                .fetchAll(db)
        }

        #expect(results.count == 1)
        #expect(results.first?.1 == true)
        #expect(results.first?.2 == "Completed")
    }

    @Test("UPDATE with no matches returns empty")
    func updateNoMatches() async throws {
        let results = try await db.write { db in
            try await Reminder
                .where { $0.id == 999 }
                .update { $0.isCompleted = true }
                .returning { $0.id }
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
                .returning { ($0.title, $0.remindersListID, $0.isFlagged) }
                .fetchAll(db)
        }

        #expect(results.count == 3) // Home list has 3 reminders
        #expect(results.allSatisfy { $0.2 == true })
    }

    @Test("UPDATE all rows")
    func updateAllRows() async throws {
        let results = try await db.write { db in
            try await Reminder
                .update { $0.isFlagged = false }
                .returning { $0.isFlagged }
                .fetchAll(db)
        }

        #expect(results.count == 6)
        #expect(results.allSatisfy { $0 == false })
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
                .returning { $0 }
                .fetchOne(db)
        }

        #expect(updated?.isCompleted == true)
    }

    @Test("UPDATE with text concatenation")
    func updateTextConcat() async throws {
        let result = try await db.write { db in
            try await Reminder
                .where { $0.id == 1 }
                .update { $0.notes = $0.notes.concatenated(with: " - Updated") }
                .returning { ($0.id, $0.notes) }
                .fetchOne(db)
        }

        #expect(result?.0 == 1)
        #expect(result?.1 == "Milk, Eggs, Apples - Updated")
    }
}
