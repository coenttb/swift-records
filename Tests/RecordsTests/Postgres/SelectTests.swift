// import Foundation
// import RecordsTestSupport
// import Testing
//
// @Suite("SELECT Tests")
// struct SelectTests {
//
//    @Test("Basic SELECT all columns")
//    func selectAll() {
//        assertQuery(
//            Tag.all,
//            sql: #"SELECT "tags"."id", "tags"."title" FROM "tags""#
//        )
//    }
//
//    @Test("SELECT with DISTINCT")
//    func selectDistinct() {
//        assertQuery(
//            Reminder.distinct().select(\.priority),
//            sql: #"SELECT DISTINCT "reminders"."priority" FROM "reminders""#
//        )
//    }
//
//    @Test("SELECT specific columns")
//    func selectColumns() {
//        assertQuery(
//            Reminder.select { ($0.id, $0.title) },
//            sql: #"SELECT "reminders"."id", "reminders"."title" FROM "reminders""#
//        )
//    }
//
//    @Test("SELECT with WHERE clause")
//    func selectWithWhere() {
//        assertQuery(
//            Reminder.where { $0.isCompleted },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE "reminders"."isCompleted""#
//        )
//    }
//
//    @Test("SELECT with complex WHERE")
//    func selectWithComplexWhere() {
//        assertQuery(
//            Reminder.where { $0.isCompleted && $0.priority == Priority.high },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."isCompleted" AND ("reminders"."priority" = $1))"#
//        )
//    }
//
//    @Test("SELECT with ORDER BY")
//    func selectWithOrderBy() {
//        assertQuery(
//            Reminder.all.order(by: \.title),
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" ORDER BY "reminders"."title""#
//        )
//    }
//
//    @Test("SELECT with ORDER BY DESC")
//    func selectWithOrderByDesc() {
//        assertQuery(
//            Reminder.all.order { $0.title.desc() },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" ORDER BY "reminders"."title" DESC"#
//        )
//    }
//
//    @Test("SELECT with LIMIT")
//    func selectWithLimit() {
//        assertQuery(
//            Reminder.all.limit(5),
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" LIMIT $1"#
//        )
//    }
//
//    @Test("SELECT with LIMIT and OFFSET")
//    func selectWithLimitOffset() {
//        assertQuery(
//            Reminder.all.limit(5, offset: 10),
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" LIMIT $1 OFFSET $2"#
//        )
//    }
//
//    @Test("SELECT with GROUP BY")
//    func selectWithGroupBy() {
//        assertQuery(
//            Reminder.group(by: \.remindersListID).select { $0.remindersListID },
//            sql: #"SELECT "reminders"."remindersListID" FROM "reminders" GROUP BY "reminders"."remindersListID""#
//        )
//    }
//
//    @Test("SELECT with aggregate functions")
//    func selectWithAggregates() {
//        assertQuery(
//            Reminder.select { $0.id.count() },
//            sql: #"SELECT count("reminders"."id") FROM "reminders""#
//        )
//
//        assertQuery(
//            Reminder.select { $0.priority.max() },
//            sql: #"SELECT max("reminders"."priority") FROM "reminders""#
//        )
//    }
//
//    @Test("SELECT with HAVING clause")
//    func selectWithHaving() {
//        assertQuery(
//            Reminder
//                .group(by: \.remindersListID)
//                .having { $0.id.count() > 2 }
//                .select { ($0.remindersListID, $0.id.count()) },
//            sql: #"SELECT "reminders"."remindersListID", count("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID" HAVING (count("reminders"."id") > $1)"#
//        )
//    }
//
//    @Test("SELECT with subquery")
//    func selectWithSubquery() {
//        let maxPriority = Reminder.select { $0.priority.max() }
//        assertQuery(
//            Reminder.where { $0.priority == maxPriority },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."priority" = (  SELECT max("reminders"."priority")  FROM "reminders" ))"#
//        )
//    }
//
//    @Test("SELECT with NULL checks")
//    func selectWithNullChecks() {
//        assertQuery(
//            Reminder.where { $0.assignedUserID == nil },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."assignedUserID" IS NULL)"#
//        )
//
//        assertQuery(
//            Reminder.where { $0.assignedUserID != nil },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."assignedUserID" IS NOT NULL)"#
//        )
//    }
//
//    @Test("SELECT with IN clause")
//    func selectWithIn() {
//        let priorities: [Priority?] = [.low, .high]
//        assertQuery(
//            Reminder.where { $0.priority.in(priorities) },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."priority" IN ($1, $2))"#
//        )
//    }
//
//    @Test("SELECT with BETWEEN")
//    func selectWithBetween() {
//        assertQuery(
//            Reminder.where { $0.id.between(1, and: 10) },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."id" BETWEEN $1 AND $2)"#
//        )
//    }
//
//    @Test("SELECT with LIKE pattern")
//    func selectWithLike() {
//        assertQuery(
//            Reminder.where { $0.title.like("%groceries%") },
//            sql: #"SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt" FROM "reminders" WHERE ("reminders"."title" LIKE $1)"#
//        )
//    }
// }
//
//
// extension SnapshotTests {
//    @Suite struct SelectTests {
//        //
//        @Test func count() {
//            assertInlineSnapshot(
//                of: Reminder.count(),
//                as: .sql
//            ) {
//                """
//                SELECT count(*)
//                FROM "reminders"
//                """
//            }
//        }
//        //
//        @Test func countFilter() {
//            assertInlineSnapshot(
//                of: Reminder.count { !$0.isCompleted },
//                as: .sql
//            ) {
//                """
//                SELECT count(*) FILTER (WHERE NOT ("reminders"."isCompleted"))
//                FROM "reminders"
//                """
//            }
//        }
//        
//        @Test func whereAnd() {
//            assertInlineSnapshot(
//                of: Reminder.where(\.isCompleted).and(.where(\.isFlagged))
//                    .count(),
//                as: .sql
//            ) {
//                """
//                SELECT count(*)
//                FROM "reminders"
//                WHERE ("reminders"."isCompleted") AND ("reminders"."isFlagged")
//                """
//            }
//        }
//        
//        @Test func whereOr() {
//            assertInlineSnapshot(
//                of: Reminder.where(\.isCompleted).or(.where(\.isFlagged))
//                    .count(),
//                as: .sql
//            ) {
//                """
//                SELECT count(*)
//                FROM "reminders"
//                WHERE ("reminders"."isCompleted") OR ("reminders"."isFlagged")
//                """
//            }
//        }
//        
//        @Test func group() {
//            assertInlineSnapshot(
//                of: Reminder.select { ($0.isCompleted, $0.id.count()) }.group(by: \.isCompleted),
//                as: .sql
//            ) {
//                """
//                SELECT "reminders"."isCompleted", count("reminders"."id")
//                FROM "reminders"
//                GROUP BY "reminders"."isCompleted"
//                """
//            }
//        }
//        
//        @Test func having() {
//            assertInlineSnapshot(
//                of: Reminder
//                    .select { ($0.isCompleted, $0.id.count()) }
//                    .group(by: \.isCompleted)
//                    .having { $0.id.count() > 3 },
//                as: .sql
//            ) {
//                """
//                SELECT "reminders"."isCompleted", count("reminders"."id")
//                FROM "reminders"
//                GROUP BY "reminders"."isCompleted"
//                HAVING (count("reminders"."id") > 3)
//                """
//            }
//        }
//        
//        @Test func havingConditionalTrue() {
//            let includeConditional: Bool = true
//            assertInlineSnapshot(
//                of: Reminder
//                    .select { ($0.isCompleted, $0.id.count()) }
//                    .group(by: \.isCompleted)
//                    .having {
//                        if includeConditional {
//                            $0.id.count() > 3
//                        }
//                    },
//                as: .sql
//            ) {
//                """
//                SELECT "reminders"."isCompleted", count("reminders"."id")
//                FROM "reminders"
//                GROUP BY "reminders"."isCompleted"
//                HAVING (count("reminders"."id") > 3)
//                """
//            }
//        }
//        
//        @Test func havingConditionalFalse() {
//            let includeConditional: Bool = false
//            assertInlineSnapshot(
//                of: Reminder
//                    .select { ($0.isCompleted, $0.id.count()) }
//                    .group(by: \.isCompleted)
//                    .having {
//                        if includeConditional {
//                            $0.id.count() > 3
//                        }
//                    },
//                as: .sql
//            ) {
//                """
//                SELECT "reminders"."isCompleted", count("reminders"."id")
//                FROM "reminders"
//                GROUP BY "reminders"."isCompleted"
//                """
//            }
//        }
//        
//        @Test func reusableHelperOnLeftJoinedTable() {
//            assertInlineSnapshot(
//                of: RemindersList
//                    .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) }
//                    .where { $1.isHighPriority ?? false },
//                as: .sql
//            ) {
//                """
//                SELECT "remindersLists"."id", "remindersLists"."color", "remindersLists"."title", "remindersLists"."position", "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt"
//                FROM "remindersLists"
//                LEFT JOIN "reminders" ON ("remindersLists"."id" = "reminders"."remindersListID")
//                WHERE coalesce(("reminders"."priority" = 3), 0)
//                """
//            }
//        }
//    }
// }
//
// extension SnapshotTests {
//    @Suite struct SelectionTests {
//        @Test func remindersListAndReminderCount() {
//            let baseQuery =
//            RemindersList
//                .group(by: \.id)
//                .limit(2)
//                .join(Reminder.all) { $0.id.eq($1.remindersListID) }
//            
//            assertInlineSnapshot(
//                of: baseQuery
//                    .select {
//                        RemindersListAndReminderCount.Columns(remindersList: $0, remindersCount: $1.id.count())
//                    },
//                as: .sql
//            ) {
//                """
//                SELECT "remindersLists"."id", "remindersLists"."color", "remindersLists"."title", "remindersLists"."position" AS "remindersList", count("reminders"."id") AS "remindersCount"
//                FROM "remindersLists"
//                JOIN "reminders" ON ("remindersLists"."id" = "reminders"."remindersListID")
//                GROUP BY "remindersLists"."id"
//                LIMIT 2
//                """
//            }
//            
//            assertInlineSnapshot(
//                of: baseQuery
//                    .select { ($1.id.count(), $0) }
//                    .map { RemindersListAndReminderCount.Columns(remindersList: $1, remindersCount: $0) },
//                as: .sql
//            ) {
//                """
//                SELECT "remindersLists"."id", "remindersLists"."color", "remindersLists"."title", "remindersLists"."position" AS "remindersList", count("reminders"."id") AS "remindersCount"
//                FROM "remindersLists"
//                JOIN "reminders" ON ("remindersLists"."id" = "reminders"."remindersListID")
//                GROUP BY "remindersLists"."id"
//                LIMIT 2
//                """
//            }
//        }
//        @Test func multiAggregate() {
//            assertInlineSnapshot(
//                of: Reminder.select {
//                    Stats.Columns(
//                        completedCount: $0.count(filter: $0.isCompleted),
//                        flaggedCount: $0.count(filter: $0.isFlagged),
//                        totalCount: $0.count()
//                    )
//                },
//                as: .sql
//            ) {
//                """
//                SELECT count("reminders"."id") FILTER (WHERE "reminders"."isCompleted") AS "completedCount", count("reminders"."id") FILTER (WHERE "reminders"."isFlagged") AS "flaggedCount", count("reminders"."id") AS "totalCount"
//                FROM "reminders"
//                """
//            }
//        }
//    }
// }
