import Foundation
import RecordsTestSupport
import Testing
//
// @Suite("Scalar Functions Tests")
// struct ScalarFunctionsTests {
//  
//  @Test("COALESCE function")
//  func coalesceFunction() {
//    assertQuery(
//      Reminder.select { coalesce($0.notes, "No notes") },
//      sql: #"SELECT coalesce("reminders"."notes", $1) FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { coalesce($0.priority, Priority.low) },
//      sql: #"SELECT coalesce("reminders"."priority", $1) FROM "reminders""#
//    )
//    
//    // Multiple arguments
//    assertQuery(
//      Reminder.select { coalesce($0.notes, $0.title, "Untitled") },
//      sql: #"SELECT coalesce("reminders"."notes", "reminders"."title", $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("NULLIF function")
//  func nullifFunction() {
//    assertQuery(
//      Reminder.select { nullif($0.title, "") },
//      sql: #"SELECT nullif("reminders"."title", $1) FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { nullif($0.priority, Priority.low) },
//      sql: #"SELECT nullif("reminders"."priority", $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("String functions")
//  func stringFunctions() {
//    // LENGTH
//    assertQuery(
//      Reminder.select { length($0.title) },
//      sql: #"SELECT length("reminders"."title") FROM "reminders""#
//    )
//    
//    // UPPER/LOWER
//    assertQuery(
//      Reminder.select { upper($0.title) },
//      sql: #"SELECT upper("reminders"."title") FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { lower($0.title) },
//      sql: #"SELECT lower("reminders"."title") FROM "reminders""#
//    )
//    
//    // TRIM
//    assertQuery(
//      Reminder.select { trim($0.title) },
//      sql: #"SELECT trim("reminders"."title") FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { ltrim($0.title) },
//      sql: #"SELECT ltrim("reminders"."title") FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { rtrim($0.title) },
//      sql: #"SELECT rtrim("reminders"."title") FROM "reminders""#
//    )
//    
//    // SUBSTRING
//    assertQuery(
//      Reminder.select { substring($0.title, 1, 5) },
//      sql: #"SELECT substring("reminders"."title", $1, $2) FROM "reminders""#
//    )
//    
//    // REPLACE
//    assertQuery(
//      Reminder.select { replace($0.title, "old", "new") },
//      sql: #"SELECT replace("reminders"."title", $1, $2) FROM "reminders""#
//    )
//    
//    // CONCAT
//    assertQuery(
//      Reminder.select { concat($0.title, " - ", $0.notes) },
//      sql: #"SELECT concat("reminders"."title", $1, "reminders"."notes") FROM "reminders""#
//    )
//    
//    // String concatenation operator
//    assertQuery(
//      Reminder.select { $0.title || " suffix" },
//      sql: #"SELECT ("reminders"."title" || $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("Date/Time functions")
//  func dateTimeFunctions() {
//    // CURRENT_DATE
//    assertQuery(
//      Reminder.select { currentDate() },
//      sql: #"SELECT CURRENT_DATE FROM "reminders""#
//    )
//    
//    // CURRENT_TIMESTAMP
//    assertQuery(
//      Reminder.select { currentTimestamp() },
//      sql: #"SELECT CURRENT_TIMESTAMP FROM "reminders""#
//    )
//    
//    // NOW()
//    assertQuery(
//      Reminder.select { now() },
//      sql: #"SELECT now() FROM "reminders""#
//    )
//    
//    // DATE_PART
//    assertQuery(
//      Reminder.select { datePart("year", $0.dueDate) },
//      sql: #"SELECT date_part($1, "reminders"."dueDate") FROM "reminders""#
//    )
//    
//    // EXTRACT
//    assertQuery(
//      Reminder.select { extract(.month, from: $0.dueDate) },
//      sql: #"SELECT EXTRACT(MONTH FROM "reminders"."dueDate") FROM "reminders""#
//    )
//    
//    // AGE
//    assertQuery(
//      Reminder.select { age($0.dueDate) },
//      sql: #"SELECT age("reminders"."dueDate") FROM "reminders""#
//    )
//    
//    // DATE_TRUNC
//    assertQuery(
//      Reminder.select { dateTrunc("month", $0.dueDate) },
//      sql: #"SELECT date_trunc($1, "reminders"."dueDate") FROM "reminders""#
//    )
//  }
//  
//  @Test("Mathematical functions")
//  func mathFunctions() {
//    // ABS
//    assertQuery(
//      Reminder.select { abs($0.id) },
//      sql: #"SELECT abs("reminders"."id") FROM "reminders""#
//    )
//    
//    // ROUND
//    assertQuery(
//      Reminder.select { round($0.id, 2) },
//      sql: #"SELECT round("reminders"."id", $1) FROM "reminders""#
//    )
//    
//    // CEIL/FLOOR
//    assertQuery(
//      Reminder.select { ceil($0.id) },
//      sql: #"SELECT ceil("reminders"."id") FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { floor($0.id) },
//      sql: #"SELECT floor("reminders"."id") FROM "reminders""#
//    )
//    
//    // POWER
//    assertQuery(
//      Reminder.select { power($0.id, 2) },
//      sql: #"SELECT power("reminders"."id", $1) FROM "reminders""#
//    )
//    
//    // SQRT
//    assertQuery(
//      Reminder.select { sqrt($0.id) },
//      sql: #"SELECT sqrt("reminders"."id") FROM "reminders""#
//    )
//    
//    // MOD
//    assertQuery(
//      Reminder.select { mod($0.id, 10) },
//      sql: #"SELECT mod("reminders"."id", $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("Type casting")
//  func typeCasting() {
//    // CAST
//    assertQuery(
//      Reminder.select { cast($0.id, as: .text) },
//      sql: #"SELECT CAST("reminders"."id" AS text) FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { cast($0.title, as: .varchar(50)) },
//      sql: #"SELECT CAST("reminders"."title" AS varchar(50)) FROM "reminders""#
//    )
//    
//    // PostgreSQL :: operator
//    assertQuery(
//      Reminder.select { $0.id.castTo(.bigint) },
//      sql: #"SELECT "reminders"."id"::bigint FROM "reminders""#
//    )
//  }
//  
//  @Test("GREATEST/LEAST functions")
//  func greatestLeastFunctions() {
//    assertQuery(
//      Reminder.select { greatest($0.id, 10, 20) },
//      sql: #"SELECT greatest("reminders"."id", $1, $2) FROM "reminders""#
//    )
//    
//    assertQuery(
//      Reminder.select { least($0.id, 100) },
//      sql: #"SELECT least("reminders"."id", $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("Regular expression functions")
//  func regexFunctions() {
//    // REGEXP_MATCH
//    assertQuery(
//      Reminder.select { regexpMatch($0.title, "^[A-Z]") },
//      sql: #"SELECT regexp_match("reminders"."title", $1) FROM "reminders""#
//    )
//    
//    // REGEXP_REPLACE
//    assertQuery(
//      Reminder.select { regexpReplace($0.title, "[0-9]", "X") },
//      sql: #"SELECT regexp_replace("reminders"."title", $1, $2) FROM "reminders""#
//    )
//    
//    // REGEXP_SPLIT_TO_ARRAY
//    assertQuery(
//      Reminder.select { regexpSplitToArray($0.title, "\\s+") },
//      sql: #"SELECT regexp_split_to_array("reminders"."title", $1) FROM "reminders""#
//    )
//  }
//  
//  @Test("JSON functions")
//  func jsonFunctions() {
//    // JSON field extraction
//    assertQuery(
//      Reminder.select { jsonExtract($0.notes, "$.key") },
//      sql: #"SELECT json_extract("reminders"."notes", $1) FROM "reminders""#
//    )
//    
//    // JSON_BUILD_OBJECT
//    assertQuery(
//      Reminder.select { jsonBuildObject("id", $0.id, "title", $0.title) },
//      sql: #"SELECT json_build_object($1, "reminders"."id", $2, "reminders"."title") FROM "reminders""#
//    )
//    
//    // TO_JSON
//    assertQuery(
//      Reminder.select { toJson($0) },
//      sql: #"SELECT to_json("reminders") FROM "reminders""#
//    )
//    
//    // TO_JSONB
//    assertQuery(
//      Reminder.select { toJsonb($0) },
//      sql: #"SELECT to_jsonb("reminders") FROM "reminders""#
//    )
//  }
//  
//  @Test("UUID functions")
//  func uuidFunctions() {
//    // GEN_RANDOM_UUID
//    assertQuery(
//      Reminder.select { genRandomUuid() },
//      sql: #"SELECT gen_random_uuid() FROM "reminders""#
//    )
//  }
//  
//  @Test("Cryptographic functions")
//  func cryptoFunctions() {
//    // MD5
//    assertQuery(
//      Reminder.select { md5($0.title) },
//      sql: #"SELECT md5("reminders"."title") FROM "reminders""#
//    )
//    
//    // SHA256 (requires pgcrypto extension)
//    assertQuery(
//      Reminder.select { sha256($0.title) },
//      sql: #"SELECT encode(digest("reminders"."title", 'sha256'), 'hex') FROM "reminders""#
//    )
//  }
//  
//  @Test("Conditional functions")
//  func conditionalFunctions() {
//    // CASE expressions are handled in PostgresCaseTests
//    // Here we test other conditional functions
//    
//    // IF equivalent using CASE
//    assertQuery(
//      Reminder.select { 
//        when($0.isCompleted, then: "Done", else: "Pending")
//      },
//      sql: #"SELECT CASE WHEN "reminders"."isCompleted" THEN $1 ELSE $2 END FROM "reminders""#
//    )
//  }
// }
