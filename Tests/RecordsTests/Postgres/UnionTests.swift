import Foundation
import RecordsTestSupport
import Testing
//
// @Suite("UNION/INTERSECT/EXCEPT Tests")
// struct UnionTests {
//  
//  @Test("Basic UNION")
//  func basicUnion() {
//    let highPriority = Reminder
//      .where { $0.priority == Priority.high }
//      .select(\.title)
//    
//    let flagged = Reminder
//      .where { $0.isFlagged }
//      .select(\.title)
//    
//    assertQuery(
//      highPriority.union(flagged),
//      sql: #"SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."priority" IS $1) UNION SELECT "reminders"."title" FROM "reminders" WHERE "reminders"."isFlagged""#
//    )
//  }
//  
//  @Test("UNION ALL")
//  func unionAll() {
//    let completed = Reminder
//      .where { $0.isCompleted }
//      .select { ($0.id, $0.title) }
//    
//    let incomplete = Reminder
//      .where { !$0.isCompleted }
//      .select { ($0.id, $0.title) }
//    
//    assertQuery(
//      completed.unionAll(incomplete),
//      sql: #"SELECT "reminders"."id", "reminders"."title" FROM "reminders" WHERE "reminders"."isCompleted" UNION ALL SELECT "reminders"."id", "reminders"."title" FROM "reminders" WHERE NOT ("reminders"."isCompleted")"#
//    )
//  }
//  
//  @Test("INTERSECT")
//  func intersect() {
//    let highPriority = Reminder
//      .where { $0.priority == Priority.high }
//      .select(\.id)
//    
//    let overdue = Reminder
//      .where { $0.dueDate < Date() }
//      .select(\.id)
//    
//    assertQuery(
//      highPriority.intersect(overdue),
//      sql: #"SELECT "reminders"."id" FROM "reminders" WHERE ("reminders"."priority" IS $1) INTERSECT SELECT "reminders"."id" FROM "reminders" WHERE ("reminders"."dueDate" < $2)"#
//    )
//  }
//  
//  @Test("INTERSECT ALL")
//  func intersectAll() {
//    let list1Reminders = Reminder
//      .where { $0.remindersListID == 1 }
//      .select(\.title)
//    
//    let list2Reminders = Reminder
//      .where { $0.remindersListID == 2 }
//      .select(\.title)
//    
//    assertQuery(
//      list1Reminders.intersectAll(list2Reminders),
//      sql: #"SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."remindersListID" = $1) INTERSECT ALL SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."remindersListID" = $2)"#
//    )
//  }
//  
//  @Test("EXCEPT")
//  func except() {
//    let allReminders = Reminder.select(\.id)
//    let completedReminders = Reminder
//      .where { $0.isCompleted }
//      .select(\.id)
//    
//    assertQuery(
//      allReminders.except(completedReminders),
//      sql: #"SELECT "reminders"."id" FROM "reminders" EXCEPT SELECT "reminders"."id" FROM "reminders" WHERE "reminders"."isCompleted""#
//    )
//  }
//  
//  @Test("EXCEPT ALL")
//  func exceptAll() {
//    let allTitles = Reminder.select(\.title)
//    let highPriorityTitles = Reminder
//      .where { $0.priority == Priority.high }
//      .select(\.title)
//    
//    assertQuery(
//      allTitles.exceptAll(highPriorityTitles),
//      sql: #"SELECT "reminders"."title" FROM "reminders" EXCEPT ALL SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."priority" IS $1)"#
//    )
//  }
//  
//  @Test("Multiple UNION operations")
//  func multipleUnions() {
//    let high = Reminder
//      .where { $0.priority == Priority.high }
//      .select(\.title)
//    
//    let medium = Reminder
//      .where { $0.priority == Priority.medium }
//      .select(\.title)
//    
//    let low = Reminder
//      .where { $0.priority == Priority.low }
//      .select(\.title)
//    
//    assertQuery(
//      high.union(medium).union(low),
//      sql: #"SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."priority" IS $1) UNION SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."priority" IS $2) UNION SELECT "reminders"."title" FROM "reminders" WHERE ("reminders"."priority" IS $3)"#
//    )
//  }
//  
//  @Test("UNION with ORDER BY")
//  func unionWithOrderBy() {
//    let completed = Reminder
//      .where { $0.isCompleted }
//      .select { ($0.title, $0.updatedAt) }
//    
//    let incomplete = Reminder
//      .where { !$0.isCompleted }
//      .select { ($0.title, $0.updatedAt) }
//    
//    assertQuery(
//      completed.union(incomplete).order(by: { $0.1 }),
//      sql: #"SELECT "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE "reminders"."isCompleted" UNION SELECT "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE NOT ("reminders"."isCompleted") ORDER BY "reminders"."updatedAt""#
//    )
//  }
//  
//  @Test("UNION with LIMIT")
//  func unionWithLimit() {
//    let recent = Reminder
//      .order(by: { $0.updatedAt.desc() })
//      .limit(5)
//      .select(\.title)
//    
//    let flagged = Reminder
//      .where { $0.isFlagged }
//      .select(\.title)
//    
//    assertQuery(
//      recent.union(flagged).limit(10),
//      sql: #"SELECT "reminders"."title" FROM "reminders" ORDER BY "reminders"."updatedAt" DESC LIMIT $1 UNION SELECT "reminders"."title" FROM "reminders" WHERE "reminders"."isFlagged" LIMIT $2"#
//    )
//  }
//  
//  @Test("Complex set operations")
//  func complexSetOperations() {
//    let highPriority = Reminder
//      .where { $0.priority == Priority.high }
//      .select(\.id)
//    
//    let completed = Reminder
//      .where { $0.isCompleted }
//      .select(\.id)
//    
//    let flagged = Reminder
//      .where { $0.isFlagged }
//      .select(\.id)
//    
//    // (high priority OR flagged) AND NOT completed
//    assertQuery(
//      highPriority.union(flagged).except(completed),
//      sql: #"SELECT "reminders"."id" FROM "reminders" WHERE ("reminders"."priority" IS $1) UNION SELECT "reminders"."id" FROM "reminders" WHERE "reminders"."isFlagged" EXCEPT SELECT "reminders"."id" FROM "reminders" WHERE "reminders"."isCompleted""#
//    )
//  }
//  
//  @Test("UNION with different tables")
//  func unionDifferentTables() {
//    // Select all entity names (reminders and lists)
//    let reminderNames = Reminder.select(\.title)
//    let listNames = RemindersList.select(\.title)
//    
//    assertQuery(
//      reminderNames.union(listNames),
//      sql: #"SELECT "reminders"."title" FROM "reminders" UNION SELECT "remindersLists"."title" FROM "remindersLists""#
//    )
//  }
// }
