import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "DELETE Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct DeleteExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("DELETE with WHERE clause")
    func deleteWithWhere() async throws {
        // Verify record exists
        let before = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }
        #expect(before != nil)

        // Delete
        try await db.write { db in
            try await Reminder.where { $0.id == 1 }.delete().execute(db)
        }

        // Verify deleted
        let after = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }
        #expect(after == nil)
    }

    @Test("DELETE with RETURNING")
    func deleteWithReturning() async throws {
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.id == 2 }
                .delete()
                .returning(\.self)
                .fetchOne(db)
        }

        #expect(deleted?.id == 2)
        #expect(deleted?.title == "Haircut")

        // Verify deletion
        let count = try await db.read { db in
            try await Reminder.where { $0.id == 2 }.fetchAll(db).count
        }
        #expect(count == 0)
    }

    @Test("DELETE with complex WHERE")
    func deleteWithComplexWhere() async throws {
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.isCompleted && $0.priority == Priority.high }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 1)
    }

    @Test("DELETE with no matches")
    func deleteNoMatches() async throws {
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.id == 999 }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 0)
    }

    @Test("DELETE with foreign key (cascades)")
    func deleteWithCascade() async throws {
        // Count reminders in list 1
        let remindersBefore = try await db.read { db in
            try await Reminder.where { $0.remindersListID == 1 }.fetchAll(db)
        }
        #expect(remindersBefore.count == 3)

        // Delete the list (should cascade to reminders)
        try await db.write { db in
            try await RemindersList.where { $0.id == 1 }.delete().execute(db)
        }

        // Verify list is deleted
        let list = try await db.read { db in
            try await RemindersList.where { $0.id == 1 }.fetchOne(db)
        }
        #expect(list == nil)

        // Verify reminders are deleted (CASCADE)
        let remindersAfter = try await db.read { db in
            try await Reminder.where { $0.remindersListID == 1 }.fetchAll(db)
        }
        #expect(remindersAfter.count == 0)
    }

    @Test("DELETE all records")
    func deleteAll() async throws {
        // Delete all tags (no foreign key constraints)
        let deleted = try await db.write { db in
            try await Tag.delete().returning(\.self).fetchAll(db)
        }

        #expect(deleted.count == 4)

        // Verify all deleted
        let remaining = try await db.read { db in
            try await Tag.all.fetchAll(db)
        }
        #expect(remaining.count == 0)
    }

    // Note: PostgreSQL DELETE doesn't support ORDER BY/LIMIT directly
    // Would need: DELETE FROM reminders WHERE id IN (SELECT id FROM reminders ORDER BY id LIMIT 1)
    // Skipping this test as it's not a standard DELETE pattern

    @Test("DELETE with enum value")
    func deleteWithEnum() async throws {
        let deleted = try await db.write { db in
            try await Reminder
                .where { $0.priority == Priority.low }
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 1)
    }

    @Test("DELETE using find()")
    func deleteWithFind() async throws {
        try await db.write { db in
            try await Reminder.find(3).delete().execute(db)
        }

        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == 3 }.fetchOne(db)
        }

        #expect(reminder == nil)
    }

    @Test("DELETE using find() with sequence")
    func deleteWithFindSequence() async throws {
        let deleted = try await db.write { db in
            try await Reminder
                .find([1, 2, 3])
                .delete()
                .returning(\.self)
                .fetchAll(db)
        }

        #expect(deleted.count == 3)
        #expect(Set(deleted.map(\.id)) == Set([1, 2, 3]))

        // Verify remaining count
        let remaining = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(remaining.count == 3)
    }
}
