////
////  File.swift
////  swift-records
////
////  Created by Coen ten Thije Boonkkamp on 31/08/2025.
////
//
// import Foundation
// import Foundation
// import RecordsTestSupport
// import Testing
//
//
// extension SnapshotTests {
//    @Suite(
//        "OperatorsTests",
//        .snapshots(record: .never)
//    )
//    struct OperatorsTests {
//        @Test func coalesce() {
//            assertInlineSnapshot(of: Row.columns.a ?? Row.columns.b ?? Row.columns.c, as: .sql) {
//                """
//                coalesce("rows"."a", "rows"."b", "rows"."c")
//                """
//            }
//        }
//        
//        @Test func strings() {
//            assertInlineSnapshot(of: Row.columns.string + Row.columns.string, as: .sql) {
//                """
//                ("rows"."string" || "rows"."string")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.collate(.c), as: .sql) {
//                """
//                ("rows"."string" COLLATE "C")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.collate(.posix), as: .sql) {
//                """
//                ("rows"."string" COLLATE "POSIX")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.collate(.enUS), as: .sql) {
//                """
//                ("rows"."string" COLLATE "en_US")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.collate(.enUSutf8), as: .sql) {
//                """
//                ("rows"."string" COLLATE "en_US.utf8")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.collate(.default), as: .sql) {
//                """
//                ("rows"."string" COLLATE "default")
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.ilike("a%"), as: .sql) {
//                """
//                ("rows"."string" ILIKE 'a%')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.ilike("a_b%", escape: "_"), as: .sql) {
//                """
//                ("rows"."string" ILIKE 'a_b%' ESCAPE '_')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.like("a%"), as: .sql) {
//                """
//                ("rows"."string" LIKE 'a%')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.like("a%", escape: #"\"#), as: .sql) {
//                #"""
//                ("rows"."string" LIKE 'a%' ESCAPE '\')
//                """#
//            }
//            assertInlineSnapshot(of: Row.columns.string.hasPrefix("a"), as: .sql) {
//                """
//                ("rows"."string" LIKE 'a%')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.hasSuffix("a"), as: .sql) {
//                """
//                ("rows"."string" LIKE '%a')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.contains("a"), as: .sql) {
//                """
//                ("rows"."string" LIKE '%a%')
//                """
//            }
//            assertInlineSnapshot(of: Row.columns.string.contains("a"[...]), as: .sql) {
//                """
//                ("rows"."string" LIKE '%a%')
//                """
//            }
//            assertInlineSnapshot(of: Row.update { $0.string += "!" }, as: .sql) {
//                """
//                UPDATE "rows"
//                SET "string" = ("rows"."string" || '!')
//                """
//            }
//            assertInlineSnapshot(of: Row.update { $0.string.append("!") }, as: .sql) {
//                """
//                UPDATE "rows"
//                SET "string" = ("rows"."string" || '!')
//                """
//            }
//            assertInlineSnapshot(of: Row.update { $0.string.append(contentsOf: "!") }, as: .sql) {
//                """
//                UPDATE "rows"
//                SET "string" = ("rows"."string" || '!')
//                """
//            }
//        }
//        
//        @Test func collationWithOrderBy() {
//            assertInlineSnapshot(
//                of: Row.order { $0.string.collate(.c) },
//                as: .sql
//            ) {
//                """
//                SELECT "rows"."a", "rows"."b", "rows"."c", "rows"."bool", "rows"."string"
//                FROM "rows"
//                ORDER BY ("rows"."string" COLLATE "C")
//                """
//            }
//            assertInlineSnapshot(
//                of: Row.order { $0.string.collate(.enUS).desc() },
//                as: .sql
//            ) {
//                """
//                SELECT "rows"."a", "rows"."b", "rows"."c", "rows"."bool", "rows"."string"
//                FROM "rows"
//                ORDER BY ("rows"."string" COLLATE "en_US") DESC
//                """
//            }
//        }
//        
//        @Test func rangeContains() async throws {
//            assertInlineSnapshot(
//                of: (0...10).contains(Row.columns.c),
//                as: .sql
//            ) {
//                """
//                ("rows"."c" BETWEEN 0 AND 10)
//                """
//            }
//            assertInlineSnapshot(
//                of: Row.columns.c.between(0, and: 10),
//                as: .sql
//            ) {
//                """
//                ("rows"."c" BETWEEN 0 AND 10)
//                """
//            }
//            assertInlineSnapshot(
//                of: Reminder.where {
//                    $0.id.between(
//                        Reminder.select { $0.id.min() } ?? 0,
//                        and: (Reminder.select { $0.id.max() } ?? 0) / 3
//                    )
//                },
//                as: .sql
//            ) {
//                """
//                SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt"
//                FROM "reminders"
//                WHERE ("reminders"."id" BETWEEN coalesce((
//                  SELECT min("reminders"."id")
//                  FROM "reminders"
//                ), 0) AND (coalesce((
//                  SELECT max("reminders"."id")
//                  FROM "reminders"
//                ), 0) / 3))
//                """
//            }
//        }
//        
//        @Test func selectSubquery() {
//            assertInlineSnapshot(
//                of: Row.select { ($0.a, Row.count()) },
//                as: .sql
//            ) {
//                """
//                SELECT "rows"."a", (
//                  SELECT count(*)
//                  FROM "rows"
//                )
//                FROM "rows"
//                """
//            }
//        }
//        
//        @Test func whereSubquery() async throws {
//            assertInlineSnapshot(
//                of: Row.where {
//                    $0.c.in(Row.select { $0.bool.cast(as: Int.self) })
//                },
//                as: .sql
//            ) {
//                """
//                SELECT "rows"."a", "rows"."b", "rows"."c", "rows"."bool", "rows"."string"
//                FROM "rows"
//                WHERE ("rows"."c" IN (SELECT CAST("rows"."bool" AS INTEGER)
//                FROM "rows"))
//                """
//            }
//            assertInlineSnapshot(
//                of: Row.where {
//                    $0.c.cast() >= Row.select { $0.c.avg() ?? 0 } && $0.c.cast() > 1.0
//                },
//                as: .sql
//            ) {
//                """
//                SELECT "rows"."a", "rows"."b", "rows"."c", "rows"."bool", "rows"."string"
//                FROM "rows"
//                WHERE ((CAST("rows"."c" AS DOUBLE PRECISION) >= (
//                  SELECT coalesce(avg("rows"."c"), 0.0)
//                  FROM "rows"
//                )) AND (CAST("rows"."c" AS DOUBLE PRECISION) > 1.0))
//                """
//            }
//        }
//    }
// }
