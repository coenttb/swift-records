// import Foundation
// import RecordsTestSupport
// import Testing
//
// extension SnapshotTests {
//    @Suite struct InsertTests {
//        @Test func select() {
//            assertInlineSnapshot(
//                of: Tag.insert {
//                    $0.title
//                } select: {
//                    RemindersList.select { $0.title.lower() }
//                }
//                    .returning(\.self),
//                as: .sql
//            ) {
//                """
//                INSERT INTO "tags"
//                ("title")
//                SELECT lower("remindersLists"."title")
//                FROM "remindersLists"
//                RETURNING "id", "title"
//                """
//            }
//            
//            assertInlineSnapshot(
//                of: Tag.insert {
//                    $0.title
//                } select: {
//                    Values("vacation")
//                }
//                    .returning(\.self),
//                as: .sql
//            ) {
//                """
//                INSERT INTO "tags"
//                ("title")
//                SELECT 'vacation'
//                RETURNING "id", "title"
//                """
//            }
//        }
//        
//        @Test func upsertWithoutID() {
//            assertInlineSnapshot(
//                of: Reminder.select { $0.id.max() },
//                as: .sql
//            ) {
//                """
//                SELECT max("reminders"."id")
//                FROM "reminders"
//                """
//            }
//            
//            assertInlineSnapshot(
//                of: Reminder.upsert {
//                    Reminder.Draft(remindersListID: 1)
//                }
//                    .returning(\.self),
//                as: .sql
//            ) {
//                """
//                INSERT INTO "reminders"
//                ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
//                VALUES
//                (NULL, NULL, NULL, 0, 0, '', NULL, 1, '', '2040-02-14 23:31:30.000')
//                ON CONFLICT ("id")
//                DO UPDATE SET "assignedUserID" = "excluded"."assignedUserID", "dueDate" = "excluded"."dueDate", "isCompleted" = "excluded"."isCompleted", "isFlagged" = "excluded"."isFlagged", "notes" = "excluded"."notes", "priority" = "excluded"."priority", "remindersListID" = "excluded"."remindersListID", "title" = "excluded"."title", "updatedAt" = "excluded"."updatedAt"
//                RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
//                """
//            }
//        }
//    }
// }
//
//
// @Suite("INSERT Tests")
// struct InsertTests {
//
//    @Test("Basic INSERT with values")
//    func insertBasic() {
//        assertQuery(
//            Reminder.insert {
//                ($0.remindersListID, $0.title, $0.isCompleted)
//            } values: {
//                (1, "New Task", false)
//            },
//            sql: #"INSERT INTO "reminders" ("remindersListID", "title", "isCompleted") VALUES ($1, $2, $3)"#
//        )
//    }
//
//    @Test("INSERT with multiple values")
//    func insertMultipleValues() {
//        assertQuery(
//            Reminder.insert {
//                ($0.title, $0.remindersListID, $0.isCompleted)
//            } values: {
//                ("Task 1", 1, false)
//                ("Task 2", 1, true)
//            },
//            sql: #"INSERT INTO "reminders" ("title", "remindersListID", "isCompleted") VALUES ($1, $2, $3), ($4, $5, $6)"#
//        )
//    }
//
//    @Test("INSERT with RETURNING clause")
//    func insertReturning() {
//        assertQuery(
//            Reminder.insert {
//                ($0.remindersListID, $0.title)
//            } values: {
//                (1, "New Task")
//            }
//                .returning(\.id),
//            sql: #"INSERT INTO "reminders" ("remindersListID", "title") VALUES ($1, $2) RETURNING "id""#
//        )
//    }
//
//    @Test("INSERT with RETURNING multiple columns")
//    func insertReturningMultiple() {
//        assertQuery(
//            Reminder.insert {
//                ($0.remindersListID, $0.title)
//            } values: {
//                (1, "New Task")
//            }
//                .returning { ($0.id, $0.title, $0.updatedAt) },
//            sql: #"INSERT INTO "reminders" ("remindersListID", "title") VALUES ($1, $2) RETURNING "id", "title", "updatedAt""#
//        )
//    }
//
//    @Test("INSERT with ON CONFLICT DO NOTHING")
//    func insertOnConflictDoNothing() {
//        // Note: onConflictDoNothing is not a standard StructuredQueries API
//        // This test is commented out as it requires custom extension
//        // assertQuery(
//        //   Reminder.insert {
//        //     ($0.id, $0.remindersListID, $0.title)
//        //   } values: {
//        //     (100, 1, "New Task")
//        //   },
//        //   sql: #"INSERT INTO "reminders" ("id", "remindersListID", "title") VALUES ($1, $2, $3)"#
//        // )
//    }
//
//    @Test("INSERT with ON CONFLICT DO UPDATE")
//    func insertOnConflictDoUpdate() {
//        assertQuery(
//            Reminder.insert {
//                ($0.id, $0.remindersListID, $0.title, $0.updatedAt)
//            } values: {
//                (100, 1, "New Task", Date(timeIntervalSince1970: 0))
//            } onConflictDoUpdate: {
//                $0.title += " Copy"
//            },
//            sql: #"INSERT INTO "reminders" ("id", "remindersListID", "title", "updatedAt") VALUES ($1, $2, $3, $4) ON CONFLICT DO UPDATE SET "title" = ("reminders"."title" || $5)"#
//        )
//    }
//
//    @Test("INSERT full record")
//    func insertFullRecord() {
//        assertQuery(
//            Reminder.insert {
//                $0
//            } values: {
//                Reminder(id: 100, remindersListID: 1, title: "Check email")
//            }
//                .returning(\.id),
//            sql: #"INSERT INTO "reminders" ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt") VALUES ($1, NULL, NULL, $2, $3, $4, NULL, $5, $6, $7) RETURNING "id""#
//        )
//    }
//
//    @Test("Batch INSERT of records")
//    func insertBatchRecords() {
//        assertQuery(
//            Reminder.insert {
//                $0
//            } values: {
//                Reminder(id: 101, remindersListID: 1, title: "Task 1")
//                Reminder(id: 102, remindersListID: 1, title: "Task 2")
//                Reminder(id: 103, remindersListID: 2, title: "Task 3")
//            },
//            sql: #"INSERT INTO "reminders" ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt") VALUES ($1, NULL, NULL, $2, $3, $4, NULL, $5, $6, $7), ($8, NULL, NULL, $9, $10, $11, NULL, $12, $13, $14), ($15, NULL, NULL, $16, $17, $18, NULL, $19, $20, $21)"#
//        )
//    }
//
//    @Test("INSERT single column")
//    func insertSingleColumn() {
//        assertQuery(
//            Reminder.insert(\.remindersListID) { 1 },
//            sql: #"INSERT INTO "reminders" ("remindersListID") VALUES ($1)"#
//        )
//    }
//
//    @Test("INSERT with empty values")
//    func insertEmptyValues() {
//        assertQuery(
//            Reminder.insert { [] },
//            sql: ""
//        )
//    }
// }
