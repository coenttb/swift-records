// import Foundation
// import RecordsTestSupport
// import Testing
//
// @Suite("Advanced Features Tests")
// struct AdvancedFeaturesTests {
//
//  @Suite("PostgreSQL-Specific Features Supported by StructuredQueries")
//  struct SupportedFeatures {
//
//    @Test("PostgreSQL-specific aggregates in grouped queries")
//    func postgresAggregatesInGroupedQueries() {
//      assertQuery(
//        Reminder
//          .group(by: \.remindersListID)
//          .select { reminder in
//            (
//              reminder.remindersListID,
//              reminder.title.stringAgg(", "),
//              reminder.title.arrayAgg(),
//              reminder.id.stddev()
//            )
//          },
//        sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."title", $1), array_agg("reminders"."title"), stddev("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//      )
//    }
//
//    @Test("Boolean column transformation in complex queries")
//    func booleanHandlingInComplexQueries() {
//      assertQuery(
//        Reminder
//          .where { $0.isCompleted }
//          .select { ($0.id, $0.title, $0.isCompleted) },
//        sql: #"SELECT "reminders"."id", "reminders"."title", "reminders"."isCompleted" FROM "reminders" WHERE "reminders"."isCompleted""#
//      )
//
//      // Complex boolean conditions with grouping
//      assertQuery(
//        Reminder
//          .where { $0.isCompleted && !$0.isFlagged }
//          .group(by: \.remindersListID)
//          .select { reminder in
//            (
//              reminder.remindersListID,
//              reminder.id.count()
//            )
//          },
//        sql: #"SELECT "reminders"."remindersListID", count("reminders"."id") FROM "reminders" WHERE ("reminders"."isCompleted" AND NOT ("reminders"."isFlagged")) GROUP BY "reminders"."remindersListID""#
//      )
//    }
//
//    @Test("PostgreSQL-specific aggregates in filtered queries")
//    func aggregatesInFilteredQueries() {
//      assertQuery(
//        Reminder
//          .group(by: \.remindersListID)
//          .select { reminder in reminder.title.stringAgg(", ") },
//        sql: #"SELECT string_agg("reminders"."title", $1) FROM "reminders" GROUP BY "reminders"."remindersListID""#
//      )
//
//      // Complex aggregation with multiple PostgreSQL functions
//      assertQuery(
//        Reminder
//          .where { $0.isCompleted }
//          .group(by: \.remindersListID)
//          .select { reminder in
//            (
//              reminder.remindersListID,
//              reminder.title.arrayAgg(),
//              reminder.id.variance(),
//              reminder.id.stddev()
//            )
//          },
//        sql: #"SELECT "reminders"."remindersListID", array_agg("reminders"."title"), variance("reminders"."id"), stddev("reminders"."id") FROM "reminders" WHERE "reminders"."isCompleted" GROUP BY "reminders"."remindersListID""#
//      )
//    }
//
//    @Test("PostgreSQL INSERT with RETURNING")
//    func insertWithReturning() {
//      assertQuery(
//        Reminder
//          .insert {
//            ($0.id, $0.remindersListID, $0.title, $0.isCompleted, $0.updatedAt)
//          } values: {
//            (1, 1, "New Title", false, Date())
//          },
//        sql: #"INSERT INTO "reminders" ("id", "remindersListID", "title", "isCompleted", "updatedAt") VALUES ($1, $2, $3, $4, $5)"#
//      )
//    }
//
//    @Test("Complex query with PostgreSQL aggregates and HAVING")
//    func complexWithHaving() {
//      assertQuery(
//        Reminder
//          .group(by: \.remindersListID)
//          .having { reminder in
//            reminder.id.count() > 2
//          }
//          .select { reminder in
//            (
//              reminder.remindersListID,
//              reminder.title.stringAgg(", "),
//              reminder.id.count(),
//              reminder.id.stddev()
//            )
//          },
//        sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."title", $1), count("reminders"."id"), stddev("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID" HAVING (count("reminders"."id") > $2)"#
//      )
//    }
//  }
//
//  @Suite("CTE and Advanced SQL Pattern Documentation")
//  struct CTEPatternDocumentation {
//
//    @Test("RECURSIVE CTE SQL Pattern")
//    func recursiveCTEPattern() {
//      let expectedSQL = """
//        WITH RECURSIVE hierarchy AS (
//          SELECT id, remindersListID, title, 1 as level
//          FROM reminders
//          WHERE remindersListID = $1
//
//          UNION ALL
//
//          SELECT r.id, r.remindersListID, r.title, h.level + 1
//          FROM reminders r
//          JOIN hierarchy h ON r.remindersListID = h.id
//          WHERE h.level < $2
//        )
//        SELECT * FROM hierarchy
//        """
//
//      #expect(expectedSQL.contains("WITH RECURSIVE"))
//      #expect(expectedSQL.contains("UNION ALL"))
//    }
//
//    @Test("MATERIALIZED CTE SQL Pattern")
//    func materializedCTEPattern() {
//      let expectedSQL = """
//        WITH expensive_calculation AS MATERIALIZED (
//          SELECT
//            remindersListID,
//            string_agg(title, ', ') as all_titles,
//            array_agg(id) as all_ids,
//            stddev(id) as id_stddev
//          FROM reminders
//          GROUP BY remindersListID
//        )
//        SELECT * FROM expensive_calculation WHERE remindersListID = $1
//        """
//      #expect(expectedSQL.contains("AS MATERIALIZED"))
//      #expect(expectedSQL.contains("string_agg"))
//      #expect(expectedSQL.contains("array_agg"))
//      #expect(expectedSQL.contains("stddev"))
//    }
//
//    @Test("Data-modifying CTE SQL Pattern")
//    func dataModifyingCTEPattern() {
//      let expectedSQL = """
//        WITH updated AS (
//          UPDATE reminders
//          SET isCompleted = 1
//          WHERE remindersListID = $1 AND dueDate < $2
//          RETURNING id, title
//        ),
//        archived AS (
//          INSERT INTO archived_reminders (reminder_id, archived_at)
//          SELECT id, $3 FROM updated
//          RETURNING reminder_id
//        )
//        SELECT
//          (SELECT COUNT(*) FROM updated) as updated_count,
//          (SELECT COUNT(*) FROM archived) as archived_count
//        """
//      #expect(expectedSQL.contains("UPDATE reminders"))
//      #expect(expectedSQL.contains("INSERT INTO archived_reminders"))
//      #expect(expectedSQL.contains("RETURNING"))
//      #expect(expectedSQL.contains("FROM updated"))
//    }
//
//    @Test("LATERAL join SQL Pattern")
//    func lateralJoinPattern() {
//      let expectedSQL = """
//        WITH list_info AS (
//          SELECT id, title, position
//          FROM remindersLists
//          WHERE position < $1
//        )
//        SELECT
//          l.title as list_title,
//          r.reminder_count,
//          r.completed_count,
//          r.title_agg
//        FROM list_info l,
//        LATERAL (
//          SELECT
//            COUNT(*) as reminder_count,
//            SUM(CASE WHEN isCompleted = 1 THEN 1 ELSE 0 END) as completed_count,
//            string_agg(title, ', ') as title_agg
//          FROM reminders
//          WHERE remindersListID = l.id
//        ) r
//        """
//      #expect(expectedSQL.contains("LATERAL"))
//      #expect(expectedSQL.contains("WHERE remindersListID = l.id"))
//      #expect(expectedSQL.contains("string_agg"))
//    }
//
//    @Test("VALUES clause SQL Pattern")
//    func valuesCTEPattern() {
//      let expectedSQL = """
//        WITH priority_names (priority_value, name, description) AS (
//          VALUES
//            (0, 'Low', 'Low priority tasks'),
//            (1, 'Medium', 'Normal priority tasks'),
//            (2, 'High', 'Urgent tasks')
//        )
//        SELECT
//          r.id,
//          r.title,
//          p.name as priority_name,
//          p.description,
//          string_agg(r.title, ', ') OVER (PARTITION BY r.priority) as similar_tasks
//        FROM reminders r
//        LEFT JOIN priority_names p ON r.priority = p.priority_value
//        WHERE r.remindersListID = $1
//        """
//      #expect(expectedSQL.contains("VALUES"))
//      #expect(expectedSQL.contains("(0, 'Low', 'Low priority tasks')"))
//      #expect(expectedSQL.contains("string_agg"))
//      #expect(expectedSQL.contains("OVER (PARTITION BY"))
//    }
//  }
// }
