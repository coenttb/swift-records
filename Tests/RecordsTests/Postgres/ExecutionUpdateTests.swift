import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "UPDATE Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
)
struct ExecutionUpdateTests {
    @Dependency(\.defaultDatabase) var db

//    @Test("UPDATE with toggle and RETURNING")
//    func updateToggleWithReturning() async throws {
//        do {
//            
//            db.write { db in
//                let results = try await db.execute(
//                    Reminder
//                        .update { $0.isCompleted.toggle() }
//                        .returning { ($0.title, $0.priority, $0.isCompleted) }
//                )
//                
//                #expect(results.count == 6)
//                
//                // Verify some toggled values
//                let groceries = results.first { $0.0 == "Buy groceries" }
//                #expect(groceries?.2 == true) // Was false, now true
//                
//                let eggs = results.first { $0.0 == "Buy eggs" }
//                #expect(eggs?.2 == false) // Was true, now false
//            }
//            
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with WHERE and RETURNING")
//    func updateWithWhereAndReturning() async throws {
//        do {
//            let results = try await db.execute(
//                Reminder
//                    .where { $0.priority == 3 }
//                    .update { $0.isCompleted = true }
//                    .returning(\.$priority)
//            )
//            
//            #expect(results.count == 1)
//            #expect(results.first == 3)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with NULL values")
//    func updateWithNull() async throws {
//        do {
//            let results = try await db.execute(
//                Reminder
//                    .where { $0.id == 1 }
//                    .update { $0.assignedUserID = .null }
//                    .returning { ($0.id, $0.assignedUserID) }
//            )
//            
//            #expect(results.count == 1)
//            #expect(results.first?.0 == 1)
//            #expect(results.first?.1 == nil)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE priority with arithmetic")
//    func updatePriorityArithmetic() async throws {
//        do {
//            // First get original priorities
//            let original: [(Int, Priority?)] = try await db.execute(
//                Reminder
//                    .where { $0.priority != nil }
//                    .select { ($0.id, $0.priority) }
//            )
//            
//            // Update priorities by incrementing
//            let updated = try await db.execute(
//                Reminder
//                    .where { $0.priority != nil }
//                    .update { $0.priority = $0.priority + 1 }
//                    .returning { ($0.id, $0.priority) }
//            )
//            
//            #expect(updated.count == original.count)
//            
//            // Verify each priority was incremented
//            for (origId, origPriority) in original {
//                let updatedItem = updated.first { $0.0 == origId }
//                if let origValue = origPriority?.rawValue,
//                   let newValue = updatedItem?.1?.rawValue {
//                    #expect(newValue == origValue + 1)
//                }
//            }
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with conditional logic")
//    func updateConditional() async throws {
//        do {
//            let results = try await db.execute(
//                Reminder
//                    .update { reminder in
//                        reminder.isCompleted = CaseExpression()
//                            .when(reminder.priority == 3, true)
//                            .else(reminder.isCompleted)
//                    }
//                    .returning { ($0.title, $0.priority, $0.isCompleted) }
//            )
//            
//            #expect(results.count == 6)
//            
//            // High priority should be completed
//            let highPriority = results.filter { $0.1 == 3 }
//            #expect(highPriority.allSatisfy { $0.2 == true })
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with computed string")
//    func updateComputedString() async throws {
//        do {
//            let result = try await db.execute(
//                Reminder
//                    .where { $0.id == 1 }
//                    .update { $0.notes = $0.notes.concatenated(with: " - Updated") }
//                    .returning { ($0.id, $0.notes) }
//            )
//            
//            #expect(result.count == 1)
//            #expect(result.first?.1 == "Get flowers - Updated")
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE multiple columns")
//    func updateMultipleColumns() async throws {
//        do {
//            let now = Date()
//            let results = try await db.execute(
//                Reminder
//                    .where { $0.id == 2 }
//                    .update { reminder in
//                        reminder.isCompleted = true
//                        reminder.updatedAt = now
//                        reminder.notes = "Completed"
//                    }
//                    .returning { ($0.id, $0.isCompleted, $0.notes) }
//            )
//            
//            #expect(results.count == 1)
//            #expect(results.first?.1 == true)
//            #expect(results.first?.2 == "Completed")
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with no matches returns empty")
//    func updateNoMatches() async throws {
//        do {
//            let results = try await db.execute(
//                Reminder
//                    .where { $0.id == 999 }
//                    .update { $0.isCompleted = true }
//                    .returning(\.$id)
//            )
//            
//            #expect(results.count == 0)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with JOIN condition")
//    func updateWithJoin() async throws {
//        do {
//            // Update reminders in a specific list
//            let results = try await db.execute(
//                Reminder
//                    .where { $0.remindersListID == 1 }
//                    .update { $0.isFlagged = true }
//                    .returning { ($0.title, $0.remindersListID, $0.isFlagged) }
//            )
//            
//            #expect(results.count == 3) // Home list has 3 reminders
//            #expect(results.allSatisfy { $0.2 == true })
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with subquery in SET")
//    func updateWithSubquery() async throws {
//        do {
//            // Get the max position first
//            let maxPosition: [Int] = try await db.execute(
//                RemindersList.select { $0.position.max() }
//            )
//            
//            // Update a list to have position = max + 1
//            let results = try await db.execute(
//                RemindersList
//                    .where { $0.id == 1 }
//                    .update { list in
//                        list.position = RemindersList
//                            .select { $0.position.max() }
//                            .asSubquery() + 1
//                    }
//                    .returning { ($0.id, $0.position) }
//            )
//            
//            #expect(results.count == 1)
//            #expect(results.first?.1 == (maxPosition.first ?? 0) + 1)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE with transaction rollback")
//    func updateWithRollback() async throws {
//        do {
//            // Get original state
//            let original: [Reminder] = try await db.execute(
//                Reminder.where { $0.id == 1 }
//            )
//            
//            // Update within rollback
//            try await db.withRollback { db in
//                let updated = try await db.execute(
//                    Reminder
//                        .where { $0.id == 1 }
//                        .update { $0.title = "Changed in transaction" }
//                        .returning(\.$title)
//                )
//                #expect(updated.first == "Changed in transaction")
//            }
//            
//            // Verify rollback
//            let afterRollback: [Reminder] = try await db.execute(
//                Reminder.where { $0.id == 1 }
//            )
//            #expect(afterRollback.first?.title == original.first?.title)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("UPDATE all rows")
//    func updateAllRows() async throws {
//        do {
//            let results = try await db.execute(
//                Reminder
//                    .update { $0.isFlagged = false }
//                    .returning(\.$isFlagged)
//            )
//            
//            #expect(results.count == 6)
//            #expect(results.allSatisfy { $0 == false })
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
}
