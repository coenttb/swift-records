import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "INSERT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderSchema())
)
struct InsertExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("INSERT single Draft with RETURNING")
    func insertSingleDraft() async throws {
        let inserted = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Test List")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(inserted != nil)
        #expect(inserted?.title == "Test List")
        #expect(inserted?.id != nil)  // Auto-generated
    }

    @Test("INSERT multiple Drafts")
    func insertMultipleDrafts() async throws {
        // First insert a list
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Shopping")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(title: "Milk", remindersListID: listID)
                Reminder.Draft(title: "Eggs", remindersListID: listID)
                Reminder.Draft(title: "Bread", remindersListID: listID)
            }
            .returning { $0.id }
            .fetchAll(db)
        }

        #expect(inserted.count == 3)
        #expect(Set(inserted).count == 3)  // All different IDs
    }

    @Test("INSERT with specific column values")
    func insertWithColumns() async throws {
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Personal")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    title: "Important Task",
                    priority: .high,
                    isCompleted: false,
                    isFlagged: true,
                    remindersListID: listID
                )
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(inserted?.title == "Important Task")
        #expect(inserted?.priority == .high)
        #expect(inserted?.isCompleted == false)
        #expect(inserted?.isFlagged == true)
    }

    @Test("INSERT with NULL values")
    func insertWithNull() async throws {
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Tasks")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    title: "Task without priority",
                    priority: nil,
                    assignedUserID: nil,
                    dueDate: nil,
                    remindersListID: listID
                )
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(inserted?.priority == nil)
        #expect(inserted?.assignedUserID == nil)
        #expect(inserted?.dueDate == nil)
    }

    @Test("UPSERT with conflict on primary key")
    func upsert() async throws {
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Work")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        // First insert
        let first = try await db.write { db in
            try await Reminder.upsert {
                Reminder.Draft(id: 100, title: "Original", remindersListID: listID)
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(first?.id == 100)
        #expect(first?.title == "Original")

        // Upsert with same ID (should update)
        let second = try await db.write { db in
            try await Reminder.upsert {
                Reminder.Draft(id: 100, title: "Updated", remindersListID: listID)
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(second?.id == 100)
        #expect(second?.title == "Updated")

        // Verify only one record exists
        let count = try await db.read { db in
            try await Reminder.where { $0.id == 100 }.fetchAll(db).count
        }

        #expect(count == 1)
    }

    @Test("INSERT with RETURNING specific columns")
    func insertReturningColumns() async throws {
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Projects")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        let result = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(title: "New Project", remindersListID: listID)
            }
            .returning { ($0.id, $0.title) }
            .fetchOne(db)
        }

        #expect(result?.0 != nil)
        #expect(result?.1 == "New Project")
    }

    @Test("INSERT Draft with defaults")
    func insertWithDefaults() async throws {
        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Home")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let listID = list?.id else {
            Issue.record("Failed to create list")
            return
        }

        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    title: "Default values test",
                    remindersListID: listID
                    // All other fields use defaults
                )
            }
            .returning { $0 }
            .fetchOne(db)
        }

        // Verify defaults
        #expect(inserted?.isCompleted == false)
        #expect(inserted?.isFlagged == false)
        #expect(inserted?.notes == "")
        #expect(inserted?.priority == nil)
    }

    @Test("INSERT with foreign key reference")
    func insertWithForeignKey() async throws {
        // Create user
        let user = try await db.write { db in
            try await User.insert {
                User.Draft(name: "Alice")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        let list = try await db.write { db in
            try await RemindersList.insert {
                RemindersList.Draft(title: "Shared")
            }
            .returning { $0 }
            .fetchOne(db)
        }

        guard let userID = user?.id, let listID = list?.id else {
            Issue.record("Failed to create dependencies")
            return
        }

        // Create reminder with user assignment
        let reminder = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    title: "Assigned Task",
                    assignedUserID: userID,
                    remindersListID: listID
                )
            }
            .returning { $0 }
            .fetchOne(db)
        }

        #expect(reminder?.assignedUserID == userID)
    }
}
