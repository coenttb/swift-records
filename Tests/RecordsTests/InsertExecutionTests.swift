import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "INSERT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct InsertExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("INSERT basic Draft")
    func insertBasicDraft() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "New task"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)
        #expect(inserted.first?.title == "New task")
        #expect(inserted.first?.remindersListID == 1)
        #expect(inserted.first?.id != nil) // Auto-generated
    }

    @Test("INSERT with all fields specified")
    func insertWithAllFields() async throws {
        let now = Date()
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    assignedUserID: 1,
                    dueDate: now,
                    isCompleted: false,
                    isFlagged: true,
                    notes: "Important task",
                    priority: .high,
                    remindersListID: 2,
                    title: "Complete project",
                    updatedAt: now
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)
        let reminder = try #require(inserted.first)
        #expect(reminder.title == "Complete project")
        #expect(reminder.assignedUserID == 1)
        #expect(reminder.priority == .high)
        #expect(reminder.isFlagged == true)
        #expect(reminder.notes == "Important task")
    }

    @Test("INSERT multiple Drafts")
    func insertMultipleDrafts() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "First task"
                )
                Reminder.Draft(
                    remindersListID: 1,
                    title: "Second task"
                )
                Reminder.Draft(
                    remindersListID: 2,
                    title: "Third task"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 3)
        #expect(inserted[0].title == "First task")
        #expect(inserted[1].title == "Second task")
        #expect(inserted[2].title == "Third task")
        #expect(Set(inserted.map(\.id)).count == 3) // All have unique IDs
    }

    @Test("INSERT with NULL optional fields")
    func insertWithNullFields() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    assignedUserID: nil,
                    priority: nil,
                    remindersListID: 1,
                    title: "Unassigned task"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)
        let reminder = try #require(inserted.first)
        #expect(reminder.assignedUserID == nil)
        #expect(reminder.priority == nil)
        #expect(reminder.dueDate == nil)
    }

    @Test("INSERT with priority levels")
    func insertWithPriorities() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    priority: .low,
                    remindersListID: 1,
                    title: "Low priority"
                )
                Reminder.Draft(
                    priority: .medium,
                    remindersListID: 1,
                    title: "Medium priority"
                )
                Reminder.Draft(
                    priority: .high,
                    remindersListID: 1,
                    title: "High priority"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 3)
        #expect(inserted[0].priority == .low)
        #expect(inserted[1].priority == .medium)
        #expect(inserted[2].priority == .high)
    }

    @Test("INSERT and verify with SELECT")
    func insertAndVerify() async throws {
        // Insert new reminder
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    notes: "Test notes",
                    remindersListID: 1,
                    title: "Verify test"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        let insertedId = try #require(inserted.first?.id)

        // Verify with SELECT
        let fetched = try await db.read { db in
            try await Reminder.where { $0.id == insertedId }.fetchOne(db)
        }

        #expect(fetched != nil)
        #expect(fetched?.title == "Verify test")
        #expect(fetched?.notes == "Test notes")
    }

    @Test("INSERT with boolean flags")
    func insertWithBooleanFlags() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    isCompleted: true,
                    isFlagged: true,
                    remindersListID: 1,
                    title: "Flagged and completed"
                )
                Reminder.Draft(
                    isCompleted: false,
                    isFlagged: false,
                    remindersListID: 1,
                    title: "Not flagged or completed"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 2)
        #expect(inserted[0].isCompleted == true)
        #expect(inserted[0].isFlagged == true)
        #expect(inserted[1].isCompleted == false)
        #expect(inserted[1].isFlagged == false)
    }

    @Test("INSERT into different lists")
    func insertIntoDifferentLists() async throws {
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(remindersListID: 1, title: "Home task")
                Reminder.Draft(remindersListID: 2, title: "Work task")
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 2)
        #expect(inserted[0].remindersListID == 1)
        #expect(inserted[1].remindersListID == 2)
    }

    @Test("INSERT with date fields")
    func insertWithDates() async throws {
        let futureDate = Date().addingTimeInterval(86400) // Tomorrow
        let inserted = try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    dueDate: futureDate,
                    remindersListID: 1,
                    title: "Future task"
                )
            }
            .returning(\.self)
            .fetchAll(db)
        }

        #expect(inserted.count == 1)
        let reminder = try #require(inserted.first)
        #expect(reminder.dueDate != nil)
        // Allow 1 second tolerance for date comparison
        if let dueDate = reminder.dueDate {
            #expect(abs(dueDate.timeIntervalSince(futureDate)) < 1.0)
        }
    }

    @Test("INSERT without RETURNING")
    func insertWithoutReturning() async throws {
        // Insert without RETURNING - just verify it doesn't throw
        try await db.write { db in
            try await Reminder.insert {
                Reminder.Draft(
                    remindersListID: 1,
                    title: "No return"
                )
            }
            .execute(db)
        }

        // Verify it was inserted by counting
        let count = try await db.read { db in
            try await Reminder.where { $0.title == "No return" }.fetchAll(db)
        }

        #expect(count.count >= 1)
    }
}
