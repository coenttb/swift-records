import Foundation
import RecordsTestSupport
import Testing
//
//// Selection types must be at module level
// @Selection
// struct JoinResult {
//    let reminderTitle: String
//    let listTitle: String
// }
//
// @Selection
// struct ListCount {
//    let listId: Int
//    let listTitle: String
//    let reminderCount: Int
// }
//
// @Selection
// struct ListWithCount {
//    let listTitle: String
//    let reminderCount: Int
// }
//
// @Suite("PostgreSQL Live Database Tests", .serialized)
// struct LiveTests {
//    let db: TestDatabase
//    
//    init() async throws {
//        self.db = try await TestDatabase.create(withSampleData: true)
//    }
//    
//    deinit {
//        Task { await db.cleanup() }
//    }
//
//    @Test("Live SELECT query")
//    func liveSelect() async throws {
//        try await db.withRollback { db in
//            let reminders: [Reminder] = try await db.execute(Reminder.all)
//
//            #expect(!reminders.isEmpty)
//            #expect(reminders.first?.title != nil)
//        }
//    }
//
//    @Test("Live SELECT with WHERE")
//    func liveSelectWithWhere() async throws {
//        do {
//            try await db.withRollback { db in
//                let completed: [Reminder] = try await db.execute(
//                    Reminder.where { $0.isCompleted }
//                )
//
//                for reminder in completed {
//                    #expect(reminder.isCompleted == true)
//                }
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live JOIN query")
//    func liveJoin() async throws {
//        do {
//            // First test without custom selection to see if join works
//            let basicJoin = try await db.execute(
//                Reminder
//                    .join(RemindersList.all) { $0.remindersListID.eq($1.id) }
//            )
//
//            #expect(!basicJoin.isEmpty)
//
//            // Now test with custom selection
//            let results: [JoinResult] = try await db.execute(
//                Reminder
//                    .join(RemindersList.all) { $0.remindersListID.eq($1.id) }
//                    .select { reminder, list in
//                        JoinResult.Columns(reminderTitle: reminder.title, listTitle: list.title)
//                    }
//            )
//
//            #expect(!results.isEmpty)
//            for result in results {
//                #expect(!result.reminderTitle.isEmpty)
//                #expect(!result.listTitle.isEmpty)
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live aggregation")
//    func liveAggregation() async throws {
//        do {
//            try await db.withRollback { db in
//                let counts: [ListCount] = try await db.execute(
//                    RemindersList
//                        .group(by: \.id)
//                        .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) }
//                        .select { list, reminder in
//                            ListCount.Columns(listId: list.id, listTitle: list.title, reminderCount: reminder.id.count())
//                        }
//                )
//
//                #expect(!counts.isEmpty)
//                for count in counts {
//                    #expect(count.listId > 0)
//                    #expect(!count.listTitle.isEmpty)
//                    #expect(count.reminderCount >= 0)
//                }
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live INSERT and SELECT")
//    func liveInsertAndSelect() async throws {
//        do {
//            // First test without returning clause
//            try await db.withRollback { db in
//                // Insert a new reminder without returning
//                _ = try await db.execute(
//                    Reminder.insert {
//                        ($0.remindersListID, $0.title, $0.isCompleted, $0.updatedAt)
//                    } values: {
//                        (1, "Test Reminder Without Return", false, Date(timeIntervalSinceReferenceDate: 1_234_567_890))
//                    }
//                )
//
//                // Verify it was inserted
//                let allReminders: [Reminder] = try await db.execute(
//                    Reminder.where { $0.title == "Test Reminder Without Return" }
//                )
//
//                #expect(allReminders.count == 1)
//                #expect(allReminders.first?.title == "Test Reminder Without Return")
//            }
//
//            // Now test with returning clause
//            try await db.withRollback { db in
//                // Insert a new reminder with returning
//                let newReminder: [Reminder] = try await db.execute(
//                    Reminder.insert {
//                        ($0.remindersListID, $0.title, $0.isCompleted, $0.updatedAt)
//                    } values: {
//                        (1, "Test Reminder", false, Date(timeIntervalSinceReferenceDate: 1_234_567_890))
//                    }
//                        .returning(\.self)
//                )
//
//                #expect(newReminder.count == 1)
//                #expect(newReminder.first?.title == "Test Reminder")
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live UPDATE")
//    func liveUpdate() async throws {
//        do {
//            try await db.withRollback { db in
//                // Update reminders (without returning clause for now)
//                _ = try await db.execute(
//                    Reminder
//                        .where { $0.id == 1 }
//                        .update { $0.title = "Updated Title" }
//                )
//
//                // Verify update
//                let check: [Reminder] = try await db.execute(
//                    Reminder.where { $0.id == 1 }
//                )
//                #expect(check.first?.title == "Updated Title")
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live UPDATE with returning tuple")
//    func liveUpdateWithReturningTuple() async throws {
//        do {
//            try await db.withRollback { db in
//                // Update reminders and return tuple
//                let updated = try await db.execute(
//                    Reminder
//                        .where { $0.id == 1 }
//                        .update { $0.title = "Updated Title" }
//                        .returning { ($0.id, $0.title) }
//                )
//
//                #expect(updated.count == 1)
//                #expect(updated.first?.0 == 1)
//                #expect(updated.first?.1 == "Updated Title")
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live UPDATE with returning single column")
//    func liveUpdateWithReturningSingle() async throws {
//        do {
//            try await db.withRollback { db in
//                // Update reminders and return single column
//                let updated: [String] = try await db.execute(
//                    Reminder
//                        .where { $0.id == 1 }
//                        .update { $0.title = "Updated Title" }
//                        .returning(\.title)
//                )
//
//                #expect(updated.count == 1)
//                #expect(updated.first == "Updated Title")
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live UPDATE with returning full record")
//    func liveUpdateWithReturningRecord() async throws {
//        do {
//            try await db.withRollback { db in
//                // Update reminders and return full record
//                let updated: [Reminder] = try await db.execute(
//                    Reminder
//                        .where { $0.id == 1 }
//                        .update { $0.title = "Updated Title" }
//                        .returning(\.self)
//                )
//
//                #expect(updated.count == 1)
//                #expect(updated.first?.id == 1)
//                #expect(updated.first?.title == "Updated Title")
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live DELETE")
//    func liveDelete() async throws {
//        do {
//            try await db.withRollback { db in
//                // Create our own test data - reminders to delete
//                let testReminders: [Int] = try await db.execute(
//                    Reminder.insert {
//                        ($0.remindersListID, $0.title, $0.isCompleted, $0.updatedAt)
//                    } values: {
//                        (1, "Completed Task 1", true, Date())
//                        (1, "Completed Task 2", true, Date())
//                        (1, "Incomplete Task", false, Date())
//                    }
//                        .returning(\.id)
//                )
//
//                #expect(testReminders.count == 3)
//
//                // Count before delete
//                let countBefore: [Int] = try await db.execute(
//                    Reminder.select { $0.id.count() }
//                )
//                let initialCount = countBefore.first ?? 0
//
//                // Delete completed reminders
//                let deleted: [Int] = try await db.execute(
//                    Reminder
//                        .where { $0.isCompleted }
//                        .delete()
//                        .returning(\.id)
//                )
//
//                // Should have deleted at least our 2 completed tasks
//                #expect(deleted.count >= 2)
//
//                // Count after delete
//                let countAfter: [Int] = try await db.execute(
//                    Reminder.select { $0.id.count() }
//                )
//                let finalCount = countAfter.first ?? 0
//
//                #expect(finalCount < initialCount)
//                #expect(finalCount == initialCount - deleted.count)
//
//                // Verify our incomplete task still exists
//                let remaining: [Reminder] = try await db.execute(
//                    Reminder.where { $0.title == "Incomplete Task" }
//                )
//                #expect(remaining.count == 1)
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live transaction")
//    func liveTransaction() async throws {
//        do {
//            try await db.withRollback { db in
//                // Multiple operations in a transaction
//
//                // 1. Insert a new list
//                let newList: [RemindersList] = try await db.execute(
//                    RemindersList.insert {
//                        ($0.title, $0.color, $0.position)
//                    } values: {
//                        ("Test List", 0xFF0000, 99)
//                    }
//                        .returning(\.self)
//                )
//
//                guard let listId = newList.first?.id else {
//                    Issue.record("Failed to insert list")
//                    return
//                }
//
//                // 2. Insert reminders for the new list
//                let newReminders: [Int] = try await db.execute(
//                    Reminder.insert {
//                        ($0.remindersListID, $0.title, $0.updatedAt)
//                    } values: {
//                        (listId, "Task 1", Date(timeIntervalSinceReferenceDate: 1_234_567_890))
//                        (listId, "Task 2", Date(timeIntervalSinceReferenceDate: 1_234_567_890))
//                        (listId, "Task 3", Date(timeIntervalSinceReferenceDate: 1_234_567_890))
//                    }
//                        .returning(\.id)
//                )
//
//                #expect(newReminders.count == 3)
//
//                // 3. Verify the inserts
//                let listWithCount: [ListWithCount] = try await db.execute(
//                    RemindersList
//                        .where { $0.id == listId }
//                        .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) }
//                        .group(by: { list, _ in list.id })
//                        .select { list, reminder in
//                            ListWithCount.Columns(listTitle: list.title, reminderCount: reminder.id.count())
//                        }
//                )
//
//                #expect(listWithCount.first?.listTitle == "Test List")
//                #expect(listWithCount.first?.reminderCount == 3)
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//
//    @Test("Live subquery")
//    func liveSubquery() async throws {
//        do {
//            try await db.withRollback { db in
//                // Find lists with more than 1 reminder
//                let busyLists: [RemindersList] = try await db.execute(
//                    RemindersList
//                        .where { list in
//                            list.id.in(
//                                Reminder
//                                    .group(by: \.remindersListID)
//                                    .having { $0.id.count() > 1 }
//                                    .select(\.remindersListID)
//                            )
//                        }
//                )
//
//                // The test data has lists with multiple reminders, so we expect some results
//                #expect(!busyLists.isEmpty)
//
//                // Verify each list actually has multiple reminders
//                for list in busyLists {
//                    let reminderCount: [Int] = try await db.execute(
//                        Reminder
//                            .where { $0.remindersListID == list.id }
//                            .select { $0.id.count() }
//                    )
//                    #expect((reminderCount.first ?? 0) > 1)
//                }
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
// }
