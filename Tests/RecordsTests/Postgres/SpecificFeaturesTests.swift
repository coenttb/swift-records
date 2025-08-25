import Foundation
import RecordsTestSupport
import Testing
//
// @Suite("PostgreSQL-Specific Features Tests")
// struct SpecificFeaturesTests {
//  
//  @Test("JSONB operations")
//  func jsonbOperations() {
//    // JSON containment operator @>
//    let jsonValue = #"{"key": "value"}"#
//    assertQuery(
//      #sql("""
//        SELECT * FROM "postgresDataTypes" 
//        WHERE "jsonData" @> \(jsonValue)
//        """),
//      sql: #"SELECT * FROM "postgresDataTypes" WHERE "jsonData" @> $1"#
//    )
//    
//    // JSON field extraction ->
//    assertQuery(
//      #sql("""
//        SELECT "jsonData" -> 'key' FROM "postgresDataTypes"
//        """),
//      sql: #"SELECT "jsonData" -> 'key' FROM "postgresDataTypes""#
//    )
//    
//    // JSON path extraction #>
//    assertQuery(
//      #sql("""
//        SELECT "jsonData" #> '{nested,data}' FROM "postgresDataTypes"
//        """),
//      sql: #"SELECT "jsonData" #> '{nested,data}' FROM "postgresDataTypes""#
//    )
//  }
//  
//  @Test("Array operations")
//  func arrayOperations() {
//    // Array contains @>
//    let tag = "swift"
//    assertQuery(
//      #sql("""
//        SELECT * FROM "postgresDataTypes" 
//        WHERE "tags" @> \(raw: "ARRAY['")\(bind: tag)\(raw: "']::text[]")
//        """),
//      sql: #"SELECT * FROM "postgresDataTypes" WHERE "tags" @> ARRAY['swift']::text[]"#
//    )
//    
//    // Array overlap &&
//    let tag1 = "swift"
//    let tag2 = "rust"
//    assertQuery(
//      #sql("""
//        SELECT * FROM "postgresDataTypes" 
//        WHERE "tags" && \(raw: "ARRAY['")\(bind: tag1)\(raw: "', '")\(bind: tag2)\(raw: "']::text[]")
//        """),
//      sql: #"SELECT * FROM "postgresDataTypes" WHERE "tags" && ARRAY['swift', 'rust']::text[]"#
//    )
//    
//    // ANY operator
//    let anyTag = "swift"
//    assertQuery(
//      #sql("""
//        SELECT * FROM "postgresDataTypes" 
//        WHERE \(bind: anyTag) = ANY("tags")
//        """),
//      sql: #"SELECT * FROM "postgresDataTypes" WHERE $1 = ANY("tags")"#
//    )
//  }
//  
//  @Test("UUID operations")
//  func uuidOperations() {
//    let uuid = UUID()
//    assertQuery(
//      #sql("""
//        INSERT INTO "postgresDataTypes" ("id", "uuid", "createdAt") 
//        VALUES (\(1), \(uuid), \(Date()))
//        """),
//      sql: #"INSERT INTO "postgresDataTypes" ("id", "uuid", "createdAt") VALUES ($1, $2, $3)"#
//    )
//    
//    assertQuery(
//      PostgresDataTypes.where { $0.uuid == uuid },
//      sql: #"SELECT "postgresDataTypes"."id", "postgresDataTypes"."uuid", "postgresDataTypes"."jsonData", "postgresDataTypes"."tags", "postgresDataTypes"."metadata", "postgresDataTypes"."ipAddress", "postgresDataTypes"."createdAt" FROM "postgresDataTypes" WHERE "postgresDataTypes"."uuid" = $1"#
//    )
//  }
//  
//  @Test("Window functions")
//  func windowFunctions() {
//    // ROW_NUMBER() OVER
//    assertQuery(
//      #sql("""
//        SELECT "title", 
//               ROW_NUMBER() OVER (PARTITION BY "remindersListID" ORDER BY "updatedAt" DESC) as row_num
//        FROM "reminders"
//        """),
//      sql: #"SELECT "title", ROW_NUMBER() OVER (PARTITION BY "remindersListID" ORDER BY "updatedAt" DESC) as row_num FROM "reminders""#
//    )
//    
//    // RANK() and DENSE_RANK()
//    assertQuery(
//      #sql("""
//        SELECT "title", 
//               RANK() OVER (ORDER BY "priority" DESC) as rank,
//               DENSE_RANK() OVER (ORDER BY "priority" DESC) as dense_rank
//        FROM "reminders"
//        """),
//      sql: #"SELECT "title", RANK() OVER (ORDER BY "priority" DESC) as rank, DENSE_RANK() OVER (ORDER BY "priority" DESC) as dense_rank FROM "reminders""#
//    )
//    
//    // LAG and LEAD
//    assertQuery(
//      #sql("""
//        SELECT "title",
//               LAG("title", 1) OVER (ORDER BY "id") as previous_title,
//               LEAD("title", 1) OVER (ORDER BY "id") as next_title
//        FROM "reminders"
//        """),
//      sql: #"SELECT "title", LAG("title", 1) OVER (ORDER BY "id") as previous_title, LEAD("title", 1) OVER (ORDER BY "id") as next_title FROM "reminders""#
//    )
//  }
//  
//  @Test("Common Table Expressions (CTEs)")
//  func commonTableExpressions() {
//    // Basic CTE
//    assertQuery(
//      #sql("""
//        WITH high_priority AS (
//          SELECT * FROM "reminders" WHERE "priority" = \(Priority.high)
//        )
//        SELECT * FROM high_priority WHERE "isCompleted" = \(false)
//        """),
//      sql: #"WITH high_priority AS (SELECT * FROM "reminders" WHERE "priority" = $1) SELECT * FROM high_priority WHERE "isCompleted" = $2"#
//    )
//    
//    // Recursive CTE
//    assertQuery(
//      #sql("""
//        WITH RECURSIVE counter(n) AS (
//          SELECT 1
//          UNION ALL
//          SELECT n + 1 FROM counter WHERE n < \(10)
//        )
//        SELECT * FROM counter
//        """),
//      sql: #"WITH RECURSIVE counter(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM counter WHERE n < $1) SELECT * FROM counter"#
//    )
//  }
//  
//  @Test("DISTINCT ON")
//  func distinctOn() {
//    assertQuery(
//      #sql("""
//        SELECT DISTINCT ON ("remindersListID") 
//               "id", "title", "remindersListID", "updatedAt"
//        FROM "reminders"
//        ORDER BY "remindersListID", "updatedAt" DESC
//        """),
//      sql: #"SELECT DISTINCT ON ("remindersListID") "id", "title", "remindersListID", "updatedAt" FROM "reminders" ORDER BY "remindersListID", "updatedAt" DESC"#
//    )
//  }
//  
//  @Test("FILTER clause for aggregates")
//  func filterClause() {
//    assertQuery(
//      #sql("""
//        SELECT "remindersListID",
//               COUNT(*) as total,
//               COUNT(*) FILTER (WHERE "isCompleted") as completed,
//               COUNT(*) FILTER (WHERE NOT "isCompleted") as pending
//        FROM "reminders"
//        GROUP BY "remindersListID"
//        """),
//      sql: #"SELECT "remindersListID", COUNT(*) as total, COUNT(*) FILTER (WHERE "isCompleted") as completed, COUNT(*) FILTER (WHERE NOT "isCompleted") as pending FROM "reminders" GROUP BY "remindersListID""#
//    )
//  }
//  
//  @Test("GROUPING SETS")
//  func groupingSets() {
//    assertQuery(
//      #sql("""
//        SELECT "remindersListID", "priority", COUNT(*)
//        FROM "reminders"
//        GROUP BY GROUPING SETS (
//          ("remindersListID"),
//          ("priority"),
//          ("remindersListID", "priority"),
//          ()
//        )
//        """),
//      sql: #"SELECT "remindersListID", "priority", COUNT(*) FROM "reminders" GROUP BY GROUPING SETS (("remindersListID"), ("priority"), ("remindersListID", "priority"), ())"#
//    )
//  }
//  
//  @Test("Full-text search")
//  func fullTextSearch() {
//    let searchQuery = "groceries & buy"
//    assertQuery(
//      #sql("""
//        SELECT * FROM "reminders"
//        WHERE to_tsvector('english', "title" || ' ' || "notes") @@ to_tsquery('english', \(searchQuery))
//        """),
//      sql: #"SELECT * FROM "reminders" WHERE to_tsvector('english', "title" || ' ' || "notes") @@ to_tsquery('english', $1)"#
//    )
//  }
//  
//  @Test("INET/CIDR operations")
//  func inetOperations() {
//    assertQuery(
//      #sql("""
//        SELECT * FROM "postgresDataTypes"
//        WHERE "ipAddress" << inet '192.168.0.0/16'
//        """),
//      sql: #"SELECT * FROM "postgresDataTypes" WHERE "ipAddress" << inet '192.168.0.0/16'"#
//    )
//  }
//  
//  @Test("INTERVAL operations")
//  func intervalOperations() {
//    assertQuery(
//      #sql("""
//        SELECT * FROM "reminders"
//        WHERE "dueDate" < CURRENT_TIMESTAMP + INTERVAL '7 days'
//        """),
//      sql: #"SELECT * FROM "reminders" WHERE "dueDate" < CURRENT_TIMESTAMP + INTERVAL '7 days'"#
//    )
//  }
//  
//  @Test("Array aggregates")
//  func arrayAggregates() {
//    assertQuery(
//      #sql("""
//        SELECT "remindersListID", 
//               array_agg("title" ORDER BY "updatedAt" DESC) as titles
//        FROM "reminders"
//        GROUP BY "remindersListID"
//        """),
//      sql: #"SELECT "remindersListID", array_agg("title" ORDER BY "updatedAt" DESC) as titles FROM "reminders" GROUP BY "remindersListID""#
//    )
//  }
//  
//  @Test("JSON aggregates")
//  func jsonAggregates() {
//    assertQuery(
//      #sql("""
//        SELECT "remindersListID",
//               json_agg(json_build_object('id', "id", 'title', "title")) as reminders
//        FROM "reminders"
//        GROUP BY "remindersListID"
//        """),
//      sql: #"SELECT "remindersListID", json_agg(json_build_object('id', "id", 'title', "title")) as reminders FROM "reminders" GROUP BY "remindersListID""#
//    )
//  }
// }
