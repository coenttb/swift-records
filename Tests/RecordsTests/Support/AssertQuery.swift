import Dependencies
import Records
import RecordsTestSupport
import StructuredQueriesPostgresCore

/// Convenience wrapper for assertQuery that auto-injects database dependency.
///
/// This wrapper automatically provides the database connection, allowing for cleaner test code.
///
/// ```swift
/// @Suite(
///   "My Tests",
///   .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
/// )
/// struct MyTests {
///   @Test func findByID() async {
///     await assertQuery(
///       Reminder.find(1).select { ($0.id, $0.title) }
///     ) {
///       """
///       SELECT "reminders"."id", "reminders"."title"
///       FROM "reminders"
///       WHERE ("reminders"."id") IN ((1))
///       """
///     } results: {
///       """
///       ┌───┬─────────────┐
///       │ 1 │ "Groceries" │
///       └───┴─────────────┘
///       """
///     }
///   }
/// }
/// ```
func assertQuery<each V: QueryRepresentable>(
    _ query: some Statement<(repeat each V)>,
    sql: (() -> String)? = nil,
    results: (() -> String)? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column
) async where repeat each V: Sendable, repeat (each V).QueryOutput: Sendable {
    @Dependency(\.defaultDatabase) var db
    
    await RecordsTestSupport.assertQuery(
        query,
        execute: { statement in
            try await db.read { db in
                try await db.fetchAll(statement)
            }
        },
        sql: sql,
        results: results,
        snapshotTrailingClosureOffset: 0,
        fileID: fileID,
        filePath: filePath,
        function: function,
        line: line,
        column: column
    )
}
