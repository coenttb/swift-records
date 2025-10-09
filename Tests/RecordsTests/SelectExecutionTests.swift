import Dependencies
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "SELECT Execution Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("SELECT all records")
    func selectAll() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)
    }

    @Test("SELECT with WHERE clause")
    func selectWithWhere() async throws {
        let completed = try await db.read { db in
            try await Reminder.where { $0.isCompleted }.fetchAll(db)
        }
        #expect(completed.count == 1)
        #expect(completed.allSatisfy { $0.isCompleted })
    }

    @Test("SELECT specific columns")
    func selectColumns() async throws {
        let titles = try await db.read { db in
            try await Reminder.select { $0.title }.fetchAll(db)
        }
        #expect(titles.count == 6)
        #expect(titles.contains("Groceries"))
        #expect(titles.contains("Haircut"))
    }

    @Test("SELECT with ORDER BY")
    func selectWithOrderBy() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.order(by: \.title).fetchAll(db)
        }
        #expect(reminders.count == 6)
        #expect(reminders.first?.title == "Finish report")
    }

    @Test("SELECT with LIMIT")
    func selectWithLimit() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.limit(3).fetchAll(db)
        }
        #expect(reminders.count == 3)
    }

    @Test("SELECT with LIMIT and OFFSET")
    func selectWithLimitOffset() async throws {
        let all = try await db.read { db in
            try await Reminder.all.order(by: \.id).fetchAll(db)
        }
        let offset = try await db.read { db in
            try await Reminder.all.order(by: \.id).limit(3, offset: 2).fetchAll(db)
        }
        #expect(offset.count == 3)
        #expect(offset.first?.id == all[2].id)
    }

    @Test("SELECT with NULL checks")
    func selectWithNullChecks() async throws {
        let withoutUser = try await db.read { db in
            try await Reminder.where { $0.assignedUserID == nil }.fetchAll(db)
        }
        let withUser = try await db.read { db in
            try await Reminder.where { $0.assignedUserID != nil }.fetchAll(db)
        }
        #expect(withoutUser.count + withUser.count == 6)
    }

    @Test("SELECT with IN clause")
    func selectWithIn() async throws {
        let priorities: [Priority?] = [.low, .high]
        let reminders = try await db.read { db in
            try await Reminder.where { $0.priority.in(priorities) }.fetchAll(db)
        }
        #expect(reminders.count == 2)
        #expect(reminders.allSatisfy { $0.priority == .low || $0.priority == .high })
    }

    @Test("SELECT with LIKE pattern")
    func selectWithLike() async throws {
        let reminders = try await db.read { db in
            try await Reminder.where { $0.title.ilike("%e%") }.fetchAll(db)
        }
        #expect(reminders.count > 0)
        #expect(reminders.allSatisfy { $0.title.lowercased().contains("e") })
    }

    // TODO: Tuple selection not yet supported - need to rewrite using proper result type
    // @Test("SELECT with JOIN")
    // @Test("SELECT with GROUP BY and aggregate")
    // @Test("SELECT with HAVING clause")

    @Test("SELECT with boolean operators")
    func selectWithBooleanOperators() async throws {
        let results = try await db.read { db in
            try await Reminder
                .where { $0.isCompleted || $0.isFlagged }
                .fetchAll(db)
        }
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.isCompleted || $0.isFlagged })
    }

    @Test("SELECT with enum comparison")
    func selectWithEnum() async throws {
        let high = try await db.read { db in
            try await Reminder.where { $0.priority == Priority.high }.fetchAll(db)
        }
        #expect(high.count == 1)
        #expect(high.first?.priority == .high)
    }

    @Test("SELECT with DISTINCT")
    func selectDistinct() async throws {
        let distinctLists = try await db.read { db in
            try await Reminder.distinct().select { $0.remindersListID }.fetchAll(db)
        }
        #expect(distinctLists.count == 2)
    }

    @Test("SELECT with computed column")
    func selectWithComputedColumn() async throws {
        let highPriority = try await db.read { db in
            try await Reminder.where { $0.isHighPriority }.fetchAll(db)
        }
        #expect(highPriority.count == 1)
        #expect(highPriority.first?.priority == .high)
    }

    @Test("fetchOne returns single record")
    func fetchOne() async throws {
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == 1 }.fetchOne(db)
        }
        #expect(reminder != nil)
        #expect(reminder?.id == 1)
        #expect(reminder?.title == "Groceries")
    }

    @Test("fetchOne returns nil when no match")
    func fetchOneNoMatch() async throws {
        let reminder = try await db.read { db in
            try await Reminder.where { $0.id == 999 }.fetchOne(db)
        }
        #expect(reminder == nil)
    }

    @Test("SELECT with find()")
    func selectWithFind() async throws {
        let reminder = try await db.read { db in
            try await Reminder.find(1).fetchOne(db)
        }
        #expect(reminder != nil)
        #expect(reminder?.id == 1)
    }

    @Test("SELECT with find() sequence")
    func selectWithFindSequence() async throws {
        let reminders = try await db.read { db in
            try await Reminder.find([1, 2, 3]).fetchAll(db)
        }
        #expect(reminders.count == 3)
        #expect(reminders.map(\.id).sorted() == [1, 2, 3])
    }
}
