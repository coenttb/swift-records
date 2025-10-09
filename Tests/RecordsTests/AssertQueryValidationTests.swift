import Dependencies
import Records
import RecordsTestSupport
import Testing

@Suite(
  "assertQuery Validation",
  .dependency(\.envVars, .development),
  .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct AssertQueryValidationTests {
  @Dependency(\.defaultDatabase) var db

  @Test func simpleSelect() async {
    await assertQuery(
      Reminder.select { $0.title }.order(by: \.title).limit(3)
    ) {
      """
      SELECT "reminders"."title"
      FROM "reminders"
      ORDER BY "reminders"."title"
      LIMIT 3
      """
    } results: {
      """
      ┌─────────────────────┐
      │ "Call accountant"   │
      │ "Doctor appointment" │
      │ "Groceries"         │
      └─────────────────────┘
      """
    }
  }
}
