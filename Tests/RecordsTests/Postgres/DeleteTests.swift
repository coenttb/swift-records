import Foundation
import RecordsTestSupport
import Testing

extension SnapshotTests {
    @Suite struct DeleteTests {
        @Test func deleteAll() {
            assertInlineSnapshot(
                of: Reminder.delete().returning(\.id),
                as: .sql
            ) {
                """
                DELETE FROM "reminders"
                RETURNING "reminders"."id"
                """
            }

            assertInlineSnapshot(
                of: Reminder.count(),
                as: .sql
            ) {
                """
                SELECT count(*)
                FROM "reminders"
                """
            }
        }

        @Test func deleteID1() {
            assertInlineSnapshot(
                of: Reminder.delete().where { $0.id == 1 }.returning(\.self),
                as: .sql
            ) {
                """
                DELETE FROM "reminders"
                WHERE ("reminders"."id" = 1)
                RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
                """
            }

            assertInlineSnapshot(
                of: Reminder.count(),
                as: .sql
            ) {
                """
                SELECT count(*)
                FROM "reminders"
                """
            }
        }

        @Test func primaryKey() {
            assertInlineSnapshot(
                of: Reminder.delete(Reminder(id: 1, remindersListID: 1)),
                as: .sql
            ) {
                """
                DELETE FROM "reminders"
                WHERE ("reminders"."id" = 1)
                """
            }

            assertInlineSnapshot(
                of: Reminder.count(),
                as: .sql
            ) {
                """
                SELECT count(*)
                FROM "reminders"
                """
            }
        }
    }
}

@Suite(
    "DELETE Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
)
 struct DeleteTests {

//    @Test("Basic DELETE all rows")
//    func deleteAll() {
//        assertQuery(
//            Reminder.delete(),
//            sql: #"DELETE FROM "reminders""#
//        )
//    }
//
//    @Test("DELETE with WHERE clause")
//    func deleteWithWhere() async throws {
//        try await assertExecute(
//            Reminder
//                .where { $0.id == 1 }
//                .delete()
//        ) {
//            """
//            DELETE FROM "reminders"
//            WHERE ("reminders"."id" = 1)
//            """
//        }
//    }
//
//    @Test("DELETE with complex WHERE")
//    func deleteComplexWhere() {
//        assertQuery(
//            Reminder
//                .where { $0.isCompleted && $0.updatedAt < Date(timeIntervalSince1970: 0) }
//                .delete(),
//            sql: #"DELETE FROM "reminders" WHERE ("reminders"."isCompleted" AND ("reminders"."updatedAt" < $1))"#
//        )
//    }
//
//    @Test("DELETE with RETURNING clause")
//    func deleteReturning() {
//        assertQuery(
//            Reminder
//                .where { $0.id == 1 }
//                .delete()
//                .returning(\.id),
//            sql: #"DELETE FROM "reminders" WHERE ("reminders"."id" = $1) RETURNING "reminders"."id""#
//        )
//    }
//
//    @Test("DELETE with RETURNING multiple columns")
//    func deleteReturningMultiple() {
//        assertQuery(
//            Reminder
//                .where { $0.isCompleted }
//                .delete()
//                .returning { ($0.id, $0.title) },
//            sql: #"DELETE FROM "reminders" WHERE "reminders"."isCompleted" RETURNING "reminders"."id", "reminders"."title""#
//        )
//    }
//
//    @Test("DELETE with IN subquery")
//    func deleteWithInSubquery() {
//        let completedIDs = Reminder
//            .where { $0.isCompleted }
//            .select(\.id)
//
//        assertQuery(
//            ReminderTag
//                .where { $0.reminderID.in(completedIDs) }
//                .delete(),
//            sql: #"DELETE FROM "remindersTags" WHERE ("remindersTags"."reminderID" IN (SELECT "reminders"."id" FROM "reminders" WHERE "reminders"."isCompleted"))"#
//        )
//    }
//
//    @Test("DELETE with primary key")
//    func deleteWithPrimaryKey() {
//        let reminder = Reminder(
//            id: 1,
//            remindersListID: 1
//        )
//
//        assertQuery(
//            Reminder.delete(reminder),
//            sql: #"DELETE FROM "reminders" WHERE ("reminders"."id" = $1)"#
//        )
//    }
//
//    @Test("DELETE with WHERE using key path")
//    func deleteWhereKeyPath() {
//        assertQuery(
//            Reminder
//                .delete()
//                .where(\.isCompleted),
//            sql: #"DELETE FROM "reminders" WHERE "reminders"."isCompleted""#
//        )
//    }
//
//    @Test("DELETE with LIMIT (through subquery)")
//    func deleteWithLimit() {
//        let oldestReminders = Reminder
//            .order(by: \.updatedAt)
//            .limit(10)
//            .select(\.id)
//
//        assertQuery(
//            Reminder
//                .where { $0.id.in(oldestReminders) }
//                .delete(),
//            sql: #"DELETE FROM "reminders" WHERE ("reminders"."id" IN (SELECT "reminders"."id" FROM "reminders" ORDER BY "reminders"."updatedAt" LIMIT $1))"#
//        )
//    }
//
//    @Test("Cascading DELETE")
//    func cascadingDelete() {
//        assertQuery(
//            RemindersList
//                .where { $0.id == 1 }
//                .delete(),
//            sql: #"DELETE FROM "remindersLists" WHERE ("remindersLists"."id" = $1)"#
//        )
//    }
//
//    @Test("DELETE with multiple conditions")
//    func deleteMultipleConditions() {
//        assertQuery(
//            Reminder
//                .where {
//                    $0.isCompleted &&
//                    $0.priority == nil &&
//                    $0.updatedAt < Date(timeIntervalSince1970: 0)
//                }
//                .delete(),
//            sql: #"DELETE FROM "reminders" WHERE (("reminders"."isCompleted" AND ("reminders"."priority" IS NULL)) AND ("reminders"."updatedAt" < $1))"#
//        )
//    }
//
//    @Test("DELETE none")
//    func deleteNone() {
//        assertQuery(
//            Reminder.none.delete(),
//            sql: ""
//        )
//    }
//
//    @Test("DELETE with RETURNING full row")
//    func deleteReturningFull() {
//        assertQuery(
//            Reminder
//                .where { $0.id == 1 }
//                .delete()
//                .returning(\.self),
//            sql: #"DELETE FROM "reminders" WHERE ("reminders"."id" = $1) RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt""#
//        )
//    }
 }
