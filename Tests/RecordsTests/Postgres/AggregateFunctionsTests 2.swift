// import Foundation
// import InlineSnapshotTesting
// import StructuredQueriesPostgres
// import RecordsTestSupport
// import Testing
//
// extension SnapshotTests {
//    @MainActor
//    @Suite struct AggregateFunctionsTests {
//        @Table
//        fileprivate struct User {
//            var id: Int
//            var name: String
//            var isAdmin: Bool
//            var age: Int?
//            var birthDate: Date?
//        }
//        
//        @Test func average() {
//            assertInlineSnapshot(of: User.columns.id.avg(), as: .sql) {
//                """
//                avg("users"."id")
//                """
//            }
//            assertInlineSnapshot(of: User.columns.age.avg(), as: .sql) {
//                """
//                avg("users"."age")
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.id.avg() },
//                as: .sql
//            ) {
//                """
//                SELECT avg("reminders"."id")
//                FROM "reminders"
//                """
//            }
//        }
//        
//        @Test func count() {
//            assertInlineSnapshot(of: User.columns.id.count(), as: .sql) {
//                """
//                count("users"."id")
//                """
//            }
//            assertInlineSnapshot(of: User.columns.id.count(distinct: true), as: .sql) {
//                """
//                count(DISTINCT "users"."id")
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.id.count() },
//                as: .sql
//            ) {
//                """
//                SELECT count("reminders"."id")
//                FROM "reminders"
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.priority.count(distinct: true) },
//                as: .sql
//            ) {
//                """
//                SELECT count(DISTINCT "reminders"."priority")
//                FROM "reminders"
//                """
//            }
//        }
//        
//        @Test func unqualifiedCount() {
//            assertInlineSnapshot(of: User.all.select { _ in .count() }, as: .sql) {
//                """
//                SELECT count(*)
//                FROM "users"
//                """
//            }
//            assertInlineSnapshot(of: User.where(\.isAdmin).count(), as: .sql) {
//                """
//                SELECT count(*)
//                FROM "users"
//                WHERE "users"."isAdmin"
//                """
//            }
//        }
//        
//        @Test func max() {
//            assertInlineSnapshot(of: User.columns.birthDate.max(), as: .sql) {
//                """
//                max("users"."birthDate")
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.dueDate.max() },
//                as: .sql
//            ) {
//                """
//                SELECT max("reminders"."dueDate")
//                FROM "reminders"
//                """
//            }
//        }
//        
//        @Test func min() {
//            assertInlineSnapshot(of: User.columns.birthDate.min(), as: .sql) {
//                """
//                min("users"."birthDate")
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.dueDate.min() },
//                as: .sql
//            ) {
//                """
//                SELECT min("reminders"."dueDate")
//                FROM "reminders"
//                """
//            }
//        }
//        
//        @Test func sum() {
//            assertInlineSnapshot(of: User.columns.id.sum(), as: .sql) {
//                """
//                sum("users"."id")
//                """
//            }
//            assertInlineSnapshot(of: User.columns.id.sum(distinct: true), as: .sql) {
//                """
//                sum(DISTINCT "users"."id")
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { #sql("sum(\($0.id))", as: Int?.self) },
//                as: .sql
//            ) {
//                """
//                SELECT sum("reminders"."id")
//                FROM "reminders"
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.select { $0.id.sum() }.where { _ in false },
//                as: .sql
//            ) {
//                """
//                SELECT sum("reminders"."id")
//                FROM "reminders"
//                WHERE 0
//                """
//            }
//        }
//        
//        @Test func aggregateOfExpression() {
//            assertInlineSnapshot(of: User.columns.name.length().count(distinct: true), as: .sql) {
//                """
//                count(DISTINCT length("users"."name"))
//                """
//            }
//            
//            assertInlineSnapshot(
//                of: Reminder.select { $0.title.length().count(distinct: true) },
//                as: .sql
//            ) {
//                """
//                SELECT count(DISTINCT length("reminders"."title"))
//                FROM "reminders"
//                """
//            }
//        }
//    }
// }
