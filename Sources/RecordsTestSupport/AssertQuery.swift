import CustomDump
import Foundation
import InlineSnapshotTesting
import Records
import StructuredQueriesPostgresCore
import StructuredQueriesPostgresTestSupport

/// An end-to-end async snapshot testing helper for PostgreSQL statements.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// await assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// ) {
///   try await db.read { try await $0.fetchAll($1) }
/// } sql: {
///   """
///   SELECT "reminders"."title" FROM "reminders"
///   ORDER BY "reminders"."title"
///   """
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - query: A statement.
///   - execute: An async closure responsible for executing the query and returning the results.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - snapshotTrailingClosureOffset: The trailing closure offset of the `sql` snapshot. Defaults
///     to `1` for invoking this helper directly, but if you write a wrapper function that automates
///     the `execute` trailing closure, you should pass `0` instead.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@_disfavoredOverload
public func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
  _ query: S,
  execute: @Sendable (S) async throws -> [(repeat (each V).QueryOutput)],
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  snapshotTrailingClosureOffset: Int = 1,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) async where repeat each V: Sendable, repeat (each V).QueryOutput: Sendable, S: Sendable {
  // SQL snapshot (synchronous - query building is sync)
  assertInlineSnapshot(
    of: query,
    as: .sql,
    message: "Query did not match",
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
      trailingClosureLabel: "sql",
      trailingClosureOffset: snapshotTrailingClosureOffset
    ),
    matches: sql,
    fileID: fileID,
    file: filePath,
    function: function,
    line: line,
    column: column
  )

  // Execute query asynchronously
  do {
    let rows = try await execute(query)
    var table = ""
    StructuredQueriesPostgresTestSupport.printTable(rows, to: &table)

    // Results snapshot (synchronous - formatting is sync)
    if !table.isEmpty {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: snapshotTrailingClosureOffset + 1
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    } else if results != nil {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results expected to be empty",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: snapshotTrailingClosureOffset + 1
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }
  } catch {
    // Error snapshot
    assertInlineSnapshot(
      of: error.localizedDescription,
      as: .lines,
      message: "Results did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "results",
        trailingClosureOffset: snapshotTrailingClosureOffset + 1
      ),
      matches: results,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
}

/// An end-to-end async snapshot testing helper for PostgreSQL statements.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// await assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// ) {
///   try await db.read { try await $0.fetchAll($1) }
/// } sql: {
///   """
///   SELECT "reminders"."title" FROM "reminders"
///   ORDER BY "reminders"."title"
///   """
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - query: A statement.
///   - execute: An async closure responsible for executing the query and returning the results.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - snapshotTrailingClosureOffset: The trailing closure offset of the `sql` snapshot. Defaults
///     to `1` for invoking this helper directly, but if you write a wrapper function that automates
///     the `execute` trailing closure, you should pass `0` instead.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
public func assertQuery<S: SelectStatement, each J: Table>(
  _ query: S,
  execute: @Sendable (Select<(S.From, repeat each J), S.From, (repeat each J)>) async throws -> [(
    S.From.QueryOutput, repeat (each J).QueryOutput
  )],
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  snapshotTrailingClosureOffset: Int = 1,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) async where S.QueryValue == (), S.Joins == (repeat each J), S.From: Sendable, S.From.QueryOutput: Sendable, repeat each J: Sendable, repeat (each J).QueryOutput: Sendable {
  await assertQuery(
    query.selectStar(),
    execute: execute,
    sql: sql,
    results: results,
    snapshotTrailingClosureOffset: snapshotTrailingClosureOffset,
    fileID: fileID,
    filePath: filePath,
    function: function,
    line: line,
    column: column
  )
}
