import Dependencies
import Records
import RecordsTestSupport
import Testing

/// Comprehensive snapshot tests for query building patterns.
///
/// This test suite mirrors upstream swift-structured-queries snapshot coverage,
/// adapted for PostgreSQL and async/await execution.
///
/// Tests are organized into extensions in separate files:
/// - SnapshotTests+Select.swift - SELECT patterns
/// - SnapshotTests+Insert.swift - INSERT patterns
/// - SnapshotTests+Update.swift - UPDATE patterns
/// - SnapshotTests+Delete.swift - DELETE patterns
@Suite(
  "Snapshot Tests",
//  .disabled(),
  .snapshots(record: .never),
  .dependencies {
    $0.envVars = .development
    $0.defaultDatabase = Database.TestDatabase.withReminderData()
  }
)
struct SnapshotTests {}
