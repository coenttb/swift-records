# Testing Guide

**Last Updated**: 2025-10-09 (Test Lifecycle & PostgresNIO-Inspired Architecture)
**Status**: ✅ Production-Ready

This document explains the testing architecture for swift-records.

**For architectural details**, see ARCHITECTURE.md.
**For historical context on how we arrived at this solution**, see HISTORY.md.

---

## Table of Contents

1. [Upstream Patterns](#upstream-patterns)
2. [PostgreSQL vs SQLite](#postgresql-vs-sqlite)
3. [Evolution of Approaches](#evolution-of-approaches)
4. [Final Solution](#final-solution)
5. [Best Practices](#best-practices)
6. [Snapshot Testing with assertQuery](#snapshot-testing-with-assertquery)
7. [Test Process Lifecycle & PostgresNIO-Inspired Architecture](#test-process-lifecycle--postgresnio-inspired-architecture)

---

## Upstream Patterns

### Package Hierarchy

swift-records follows the same architecture as sqlite-data:

```
swift-structured-queries (query language foundation)
├── SQLite variant → used by sqlite-data
└── PostgreSQL variant → used by swift-records
```

### Alignment with sqlite-data

| Aspect | sqlite-data | swift-records | Status |
|--------|-------------|---------------|--------|
| **Purpose** | SQLite database operations | PostgreSQL database operations | ✅ Aligned |
| **Query Language** | swift-structured-queries | swift-structured-queries-postgres | ✅ Aligned |
| **Test Schema** | Reminder, RemindersList | Reminder, RemindersList | ✅ Aligned |
| **Dependency Injection** | `@Dependency(\.defaultDatabase)` | `@Dependency(\.defaultDatabase)` | ✅ Aligned |
| **Test Database** | In-memory SQLite | PostgreSQL schemas | ⚠️ Adapted |
| **Parallel Execution** | Serial (`.serialized`) | **Parallel required** | ⚠️ Different |

### Key Upstream Characteristics

**swift-structured-queries** uses:
```swift
@MainActor @Suite(.serialized, .snapshots(record: .failed))
struct SnapshotTests {}
```

**sqlite-data** uses:
```swift
@Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
    @Dependency(\.defaultDatabase) var database
}
```

**Pattern**:
- ✅ Suite-level shared database
- ✅ Serial execution (`.serialized` trait)
- ✅ In-memory SQLite (instant setup)
- ✅ Manual cleanup in some tests

---

## PostgreSQL vs SQLite

### Why Upstream Patterns Don't Translate Directly

| Aspect | SQLite (Upstream) | PostgreSQL (Our Implementation) |
|--------|-------------------|--------------------------------|
| **Setup Time** | Instant (in-memory) | ~100-200ms (schema creation) |
| **Concurrency** | Serialized writes | MVCC, concurrent transactions |
| **Parallel Tests** | `.serialized` acceptable | **Required** for cmd+U |
| **Cleanup** | Drop database = instant | Schema cleanup = complex |
| **Connection Limit** | Single file | 100 connections max |

### Critical Differences

1. **SQLite serializes writes within the database** → Tests naturally queue
2. **PostgreSQL handles concurrent writes natively** → Tests should run in parallel
3. **Cmd+U requirement** → Tests must pass with Xcode's parallel execution

### PostgreSQL Advantages

- ✅ True concurrent execution
- ✅ MVCC for transaction isolation
- ✅ Production-like testing
- ✅ Connection pooling

---

## Evolution of Approaches

We tried 4 approaches before arriving at the final solution (details in HISTORY.md):

1. **❌ Per-Test DB Instances** - Connection exhaustion (220 connections needed)
2. **❌ Transaction Rollback** - Actor serialization bottleneck
3. **❌ Manual Cleanup** - TestDatabasePool actor bottleneck during parallel initialization
4. **✅ Shared Client + Schema Isolation** - Final solution

### The Final Solution

**Key Architecture**:
- **Shared PostgresClient** - All suites use ONE client (10-20 connections total)
- **Schema Isolation** - Each suite gets unique PostgreSQL schema via `SET search_path`
- **Automatic Cleanup** - EventLoopGroup shutdown via `atexit` hook

**Usage**:
```swift
@Suite(
    "My Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        let records = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(records.count == 6)
    }
}
```

**Result**: ✅ 127 tests in 19 suites pass in ~1 second with clean exit

---

## Final Solution

### Architecture Overview

**Per-Suite Database Creation**:
- Each test suite gets its own `LazyTestDatabase` instance
- Each `LazyTestDatabase` has its own `DatabaseManager` actor
- Each manager creates database **directly** bypassing shared pool
- Pre-warming prevents thundering herd problem

**Test Isolation**:
- Manual cleanup for mutation tests
- Each suite has isolated PostgreSQL schema
- Tests within suite share sample data
- No transaction rollback needed

### Database Setup Modes

Swift-records uses an extensible struct pattern for database setup modes, allowing custom initialization logic:

```swift
public struct TestDatabaseSetupMode: Sendable {
    let setup: @Sendable (any Database.Writer) async throws -> Void

    public init(setup: @escaping @Sendable (any Database.Writer) async throws -> Void) {
        self.setup = setup
    }

    // Built-in mode: Reminder schema with sample data (upstream-aligned)
    public static let withReminderData = TestDatabaseSetupMode { db in
        try await db.createReminderSchema()
        try await db.insertReminderSampleData()
    }
}
```

**Factory Method**:
```swift
// Standard setup with Reminder schema + sample data
Database.TestDatabase.withReminderData()
```

**Custom Setup Modes**:
```swift
extension Database.TestDatabaseSetupMode {
    static let myCustomSetup = TestDatabaseSetupMode { db in
        try await db.createReminderSchema()
        // Custom initialization logic
        try await db.execute("INSERT INTO reminders (title) VALUES ('Custom')")
    }
}

// Use in tests
@Suite(
    "Custom Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = try await Database.testDatabase(setupMode: .myCustomSetup)
    }
)
```

### Test Pattern

**Read-Only Tests**:
```swift
@Suite(
    "My Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myReadOnlyTest() async throws {
        let records = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(records.count == 6)
    }
}
```

**Mutation Tests**:
```swift
@Test func myInsertTest() async throws {
    let inserted = try await db.write { db in
        try await Reminder.insert {
            Reminder.Draft(remindersListID: 1, title: "New task")
        }
        .returning(\.self)
        .fetchAll(db)
    }

    #expect(inserted.count == 1)

    // Manual cleanup
    if let id = inserted.first?.id {
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }
}
```

### Sample Data

**Reminder Schema** (upstream-aligned with swift-structured-queries):
- 2 RemindersList records (Home, Work)
- 2 User records (Alice, Bob)
- 6 Reminder records
- 4 Tag records with relationships

This schema matches the test data used in Point-Free's sqlite-data package, ensuring alignment with upstream patterns.

---

## Best Practices

### 1. Choose the Right Setup Mode

**For standard tests** (recommended):
```swift
.dependencies {
    $0.envVars = .development
    $0.defaultDatabase = Database.TestDatabase.withReminderData()
}
```

**For custom schema tests**:
```swift
extension Database.TestDatabaseSetupMode {
    static let customSchema = TestDatabaseSetupMode { db in
        // Create your own schema
        try await db.execute("CREATE TABLE custom (...)")
    }
}

// Use in tests
.dependencies {
    $0.envVars = .development
    $0.defaultDatabase = try await Database.testDatabase(setupMode: .customSchema)
}
```

### 2. Clean Up Mutations

Always clean up data created by mutation tests:

```swift
@Test func insertTest() async throws {
    // Insert
    let id = try await db.write { db in
        try await Record.insert { ... }.returning(\.id).fetchOne(db)
    }

    // Verify
    #expect(id != nil)

    // Cleanup
    try await db.write { db in
        try await Record.find(id!).delete().execute(db)
    }
}
```

### 3. Use Unique Identifiers for Parallel Safety

If tests might run concurrently:

```swift
@Test func insertTest() async throws {
    let uniqueTitle = "Task-\(UUID())"

    let inserted = try await db.write { db in
        try await Reminder.insert {
            Reminder.Draft(remindersListID: 1, title: uniqueTitle)
        }
        .returning(\.self)
        .fetchAll(db)
    }

    // Cleanup by unique identifier
    try await db.write { db in
        try await Reminder.where { $0.title == uniqueTitle }.delete().execute(db)
    }
}
```

### 4. Leverage PostgreSQL-Specific Features

**Sequences**:
```swift
// Auto-generated IDs (SERIAL)
let reminder = try await Reminder.insert { ... }.returning(\.id).fetchOne(db)
```

**RETURNING clause**:
```swift
let updated = try await Reminder
    .where { $0.id == 1 }
    .update { $0.isCompleted = true }
    .returning { $0 }
    .fetchOne(db)
```

**CASCADE deletes**:
```swift
// Deleting list cascades to reminders
try await RemindersList.find(1).delete().execute(db)
```

### 5. Concurrency Testing

**Never use `try?` in concurrent tests** - it silently swallows errors:

```swift
// ❌ WRONG - hides all errors
await withTaskGroup(of: Void.self) { group in
    for i in 1...100 {
        group.addTask {
            try? await db.write { db in
                try await Record.insert { ... }.execute(db)
            }
        }
    }
}
```

**Use `withThrowingTaskGroup` to surface errors**:

```swift
// ✅ CORRECT - errors are visible
try await withThrowingTaskGroup(of: Void.self) { group in
    for i in 1...100 {
        group.addTask {
            try await db.write { db in
                try await Record.insert { ... }.execute(db)
            }
        }
    }
    try await group.waitForAll()
}
```

**Common pitfall**: A test with 67% success rate was hiding foreign key violations with `try?`. After removing `try?`, the real error became visible: using `remindersListID=3` when only IDs 1 and 2 existed.

**Note on Connection Management**: The shared PostgresClient singleton (established in the final architecture) handles connection pooling automatically. All test suites use the same shared client, which manages a pool of 10-20 connections total. This is sufficient for concurrent operations, as the client queues operations efficiently.

### 6. Lessons from Resource Pooling Patterns

**Key Insight**: `@globalActor` patterns work for **stateless** resources (like WebViews) but fail for **stateful** resources (like databases) due to data pollution.

**Our Solution**: Share infrastructure (PostgresClient), isolate data (PostgreSQL schemas)

| Aspect | Shared WebView Pool | Shared Database Pool | Our Approach |
|--------|---------------------|---------------------|--------------|
| **Pattern** | `@globalActor` | `@globalActor` | `actor` + schemas |
| **Data Isolation** | N/A (stateless) | ❌ Tests see each other's data | ✅ Schema per suite |
| **Resource Usage** | ✅ Efficient | ✅ Efficient | ✅ Efficient |
| **Test Reliability** | ✅ High | ❌ Unpredictable | ✅ High |

**Status**: ✅ 127 tests in 19 suites, 10-20 connections total, ~1 second execution, clean exit

### 7. Connection Monitoring

#### Quick Reference

**Monitor connections**:
```sql
SELECT count(*), state FROM pg_stat_activity WHERE datname = 'postgres' GROUP BY state;
```

**Expected**: 5-10 active, 5-15 idle during tests (10-20 total)

**Kill stuck connection** (emergency):
```sql
SELECT pg_terminate_backend(12345);  -- Replace with PID
```

**Clean orphaned schemas**:
```sql
SELECT nspname FROM pg_namespace WHERE nspname LIKE 'test_%';  -- List them
DROP SCHEMA test_abc123 CASCADE;  -- Delete specific schema
```

#### Debugging Hanging Tests

1. **Check connections**: `psql postgres -c "SELECT count(*) FROM pg_stat_activity;"`
2. **Add logging**: Print statements in suite `.dependencies { }` blocks
3. **Add timeouts**: Use `@Test(.timeLimit(.minutes(1)))`
4. **Last resort**: `pkill -9 xcodebuild` + cleanup orphaned schemas

#### Current Status

✅ 127 tests, 19 suites, ~1 second, 10-20 connections, clean exit

### 8. Test Organization

**By operation type**:
- `SelectExecutionTests.swift` - SELECT operations
- `InsertExecutionTests.swift` - INSERT operations
- `UpdateExecutionTests.swift` - UPDATE operations
- `DeleteExecutionTests.swift` - DELETE operations

**By feature**:
- `TransactionTests.swift` - Transaction management
- `MigrationTests.swift` - Schema migrations
- `PostgresJSONBTests.swift` - JSONB operations
- `ConcurrencyStressTests.swift` - High-concurrency scenarios (disabled by default)

---

## Snapshot Testing with assertQuery

`assertQuery` verifies both SQL generation and execution results using InlineSnapshotTesting.

### Basic Usage

```swift
@Suite("My Tests", .snapshots(record: .never), .dependencies {
    $0.envVars = .development
    $0.defaultDatabase = Database.TestDatabase.withReminderData()
})
struct MyTests {
    @Test func selectTitles() async {
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
            ┌─────────────────┐
            │ "Finish report" │
            │ "Groceries"     │
            │ "Haircut"       │
            └─────────────────┘
            """
        }
    }
}
```

### Snapshot Modes

```swift
@Suite(.snapshots(record: .never))   // CI - enforce exact matches
@Suite(.snapshots(record: .failed))  // Development - record on failure
@Suite(.snapshots(record: .all))     // Update all snapshots
```

### Parameter Pack Support

Multi-column SELECT with tuples:

```swift
await assertQuery(
    Reminder.find(1).select { ($0.id, $0.title, $0.isCompleted) }
) {
    """
    SELECT "reminders"."id", "reminders"."title", "reminders"."isCompleted"
    FROM "reminders"
    WHERE ("reminders"."id") IN ((1))
    """
} results: {
    """
    ┌────┬──────────────┬───────┐
    │ 1  │ "Groceries" │ false │
    └────┴──────────────┴───────┘
    """
}
```

### Coverage Status

**Current**: 39 tests (12% of upstream's 320+)
- ✅ Core CRUD patterns (SELECT, INSERT, UPDATE, DELETE)
- ⚠️  Advanced SELECT (basic coverage, needs JOINs, aggregates)
- ❌ Missing: CTEs, UNION, window functions, subqueries

**Next Priority**: JOIN and aggregate function snapshots

---

## Test Process Lifecycle

**Problem Solved**: Tests passed but process hung forever (never returned to shell)

**Root Cause**: NIO's `EventLoopGroup` background threads kept process alive even after tests completed

**Solution** (inspired by PostgresNIO's test suite):
- Shared `PostgresClient` singleton for all test suites
- `atexit` hook calls `EventLoopGroup.shutdownGracefully()`
- 10-20 connections total (vs 130+ with per-suite clients)

**Key Insight**: Cancelling tasks isn't enough - must shutdown EventLoopGroup for clean exit

**Status**: ✅ Clean exit, 127 tests, ~1 second

---

## Performance Characteristics

### Typical Test Run

**Per suite**:
- Schema creation: ~100-200ms (once per suite)
- Test execution: ~10-50ms per test
- Cleanup: Automatic via schema isolation

**Parallel execution**:
- 94 tests across multiple suites
- Complete in ~5-10 seconds
- No actor bottlenecks
- True concurrent execution

### Optimization Tips

1. **Group related tests** in same suite to share schema setup
2. **Use read-only tests** when possible (no cleanup needed)
3. **Pre-warm databases** with `LazyTestDatabase(preWarm: true)`
4. **Minimize mutations** to reduce cleanup overhead

---

## Comparison Matrix

| Approach | Setup Time | Concurrency | Bottleneck | Cleanup | Result |
|----------|-----------|-------------|------------|---------|--------|
| Per-test DB instances | ~200ms × 44 | ❌ | Connection exhaustion | Auto | ❌ Failed |
| Transaction rollback | ~5ms | ❌ | Actor serialization | Auto | ❌ Failed |
| Manual cleanup | ~5ms | ⚠️ | TestDatabasePool | Manual | ⚠️ Hangs |
| **Shared Client + Schemas** | ~200ms × suites | ✅ | **None** | Auto | ✅ **Works!** |

---

## Migration Guide

If you're updating existing tests to this pattern:

### Before (Transaction Rollback)
```swift
@Suite(.dependency(\.defaultDatabase, Database.TestDatabase.withReminderData()))
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        try await db.withRollback { db in
            // Test code
        }
    }
}
```

### After (Shared Client)
```swift
@Suite(
    "My Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        // Read-only: No changes needed
        let records = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }

        // Mutations: Add manual cleanup
        let id = try await db.write { db in
            try await Reminder.insert { ... }.returning(\.id).fetchOne(db)
        }

        // Cleanup
        try await db.write { db in
            try await Reminder.find(id!).delete().execute(db)
        }
    }
}
```

---

## Troubleshooting

### Tests Hang During cmd+U

**Symptom**: Tests never complete, spinners keep running

**Likely Cause**: Process exit issues or EventLoopGroup not shutting down

**Solution**: The shared PostgresClient architecture handles this automatically via `atexit` shutdown hooks. If tests still hang, check for:
- Uncancelled async tasks
- Leaked database connections
- Manual EventLoopGroup creation without shutdown

### Connection Pool Exhausted

**Symptom**: `PSQLError` about max connections

**Likely Cause**: Other processes consuming PostgreSQL connections

**Solution**:
- The shared PostgresClient uses only 10-20 connections total
- Check for other applications using PostgreSQL
- Monitor connections with `SELECT count(*) FROM pg_stat_activity`

### Foreign Key Violations

**Symptom**: `PSQLError` about foreign key constraint

**Likely Cause**: Cleanup order incorrect (deleting parent before child)

**Solution**:
- Use CASCADE deletes in schema
- Delete children before parents
- Or rely on CASCADE to handle automatically

### Sequence Not Updated

**Symptom**: Primary key conflicts on INSERT

**Cause**: Explicit IDs in sample data don't update SERIAL sequence

**Solution**: See `SEQUENCE_FIX.md` - use `pg_get_serial_sequence()` and `setval()`

---

## Related Documentation

- `HISTORY.md` - How we got here
- `ARCHITECTURE.md` - How we got here
- `README.md` - Package overview

---

## Summary

**The key insights**:

1. **Share infrastructure, isolate data** - Singleton PostgresClient for efficiency (10-20 connections), PostgreSQL schemas for isolation (per suite)
2. **Study upstream patterns** - PostgresNIO's test suite revealed EventLoopGroup shutdown requirement, sqlite-data provided Reminder schema
3. **Proper lifecycle management is critical** - EventLoopGroup.shutdownGracefully() via atexit ensures clean process exit
4. **Extensible architecture** - TestDatabaseSetupMode struct pattern allows custom initialization logic

This architecture:
- ✅ Passes cmd+U (parallel execution with 127 tests in ~1 second)
- ✅ Leverages PostgreSQL strengths (MVCC, schemas, concurrent transactions)
- ✅ Upstream-aligned (Reminder schema, assertQuery patterns)
- ✅ Clean test isolation (PostgreSQL schemas, not separate databases)
- ✅ Efficient resource usage (10-20 connections total, not per-suite)
- ✅ Full snapshot testing with assertQuery
- ✅ Parameter pack support for tuple queries
- ✅ Swift 6 strict concurrency compliant
- ✅ Clean process exit (PostgresNIO-inspired EventLoopGroup lifecycle)
- ✅ Extensible setup modes (struct pattern, not enum)

**Status**: ✅ Production-ready with comprehensive testing infrastructure, efficient resource management, and clean lifecycle
