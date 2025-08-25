// import Foundation
// import RecordsTestSupport
// import Testing
//
// @Suite("PostgreSQL-Specific Aggregate Functions Tests")
// struct AggregateFunctionsTests {
//
//  @Test("STRING_AGG function")
//  func stringAggregation() {
//    // STRING_AGG is PostgreSQL-specific
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.title.stringAgg(", ")) },
//      sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."title", $1) FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.notes.stringAgg(" | ")) },
//      sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."notes", $1) FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("ARRAY_AGG function")
//  func arrayAggregation() {
//    // ARRAY_AGG is PostgreSQL-specific
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.title.arrayAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", array_agg("reminders"."title") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.id.arrayAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", array_agg("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("JSON_AGG and JSONB_AGG functions")
//  func jsonAggregation() {
//    // JSON_AGG is PostgreSQL-specific
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.title.jsonAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", json_agg("reminders"."title") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//
//    // JSONB_AGG
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.title.jsonbAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", jsonb_agg("reminders"."title") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.notes.jsonbAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", jsonb_agg("reminders"."notes") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("Statistical functions - STDDEV")
//  func stddevFunction() {
//    // PostgreSQL-specific statistical functions
//    assertQuery(
//      Reminder.select { $0.id.stddev() },
//      sql: #"SELECT stddev("reminders"."id") FROM "reminders""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.id.stddev()) },
//      sql: #"SELECT "reminders"."remindersListID", stddev("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("Statistical functions - STDDEV_POP and STDDEV_SAMP")
//  func stddevPopAndSamp() {
//    assertQuery(
//      Reminder.select { ($0.id.stddevPop(), $0.id.stddevSamp()) },
//      sql: #"SELECT stddev_pop("reminders"."id"), stddev_samp("reminders"."id") FROM "reminders""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.id.stddevPop()) },
//      sql: #"SELECT "reminders"."remindersListID", stddev_pop("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("Statistical functions - VARIANCE")
//  func varianceFunction() {
//    assertQuery(
//      Reminder.select { $0.id.variance() },
//      sql: #"SELECT variance("reminders"."id") FROM "reminders""#
//    )
//
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.id.variance()) },
//      sql: #"SELECT "reminders"."remindersListID", variance("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("Combining PostgreSQL-specific aggregates")
//  func combinedAggregates() {
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .select { reminder in
//          (
//            reminder.remindersListID,
//            reminder.title.stringAgg(", "),
//            reminder.id.arrayAgg(),
//            reminder.id.stddev()
//          )
//        },
//      sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."title", $1), array_agg("reminders"."id"), stddev("reminders"."id") FROM "reminders" GROUP BY "reminders"."remindersListID""#
//    )
//  }
//
//  @Test("PostgreSQL aggregates with WHERE clause")
//  func aggregatesWithWhere() {
//    assertQuery(
//      Reminder
//        .where { $0.isCompleted }
//        .group(by: \.remindersListID)
//        .select { reminder in (reminder.remindersListID, reminder.title.stringAgg(", ")) },
//      sql: #"SELECT "reminders"."remindersListID", string_agg("reminders"."title", $1) FROM "reminders" WHERE "reminders"."isCompleted" GROUP BY "reminders"."remindersListID""#
//    )
//
//    assertQuery(
//      Reminder
//        .where { $0.priority == Priority.high }
//        .select { $0.id.stddev() },
//      sql: #"SELECT stddev("reminders"."id") FROM "reminders" WHERE ("reminders"."priority" = $1)"#
//    )
//  }
//
//  @Test("PostgreSQL aggregates with HAVING clause")
//  func aggregatesWithHaving() {
//    // Using standard count() with PostgreSQL-specific aggregates
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .having { $0.id.count() > 2 }
//        .select { reminder in (reminder.remindersListID, reminder.title.arrayAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", array_agg("reminders"."title") FROM "reminders" GROUP BY "reminders"."remindersListID" HAVING (count("reminders"."id") > $1)"#
//    )
//  }
//
//  @Test("PostgreSQL aggregates with ORDER BY")
//  func aggregatesWithOrderBy() {
//    assertQuery(
//      Reminder
//        .group(by: \.remindersListID)
//        .order(by: { reminder in reminder.remindersListID })
//        .select { reminder in (reminder.remindersListID, reminder.title.jsonAgg()) },
//      sql: #"SELECT "reminders"."remindersListID", json_agg("reminders"."title") FROM "reminders" GROUP BY "reminders"."remindersListID" ORDER BY "reminders"."remindersListID""#
//    )
//  }
// }
