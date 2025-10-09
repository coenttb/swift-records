# Testing Guide

**Last Updated**: 2025-10-08 (ResourcePool Integration)
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

We tried 4 different approaches before finding the solution:

### ❌ Approach 1: Per-Test Database Instances

**Implementation**:
```swift
@Test(
    "My test",
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
func myTest() async throws {
    @Dependency(\.defaultDatabase) var db
    // Each test creates its own Database.Writer actor
}
```

**Why it failed**:
- Each test created its own `Database.Writer` actor
- Each actor had 5 connections in its pool
- 44 tests × 5 connections = 220 connections
- PostgreSQL max connections: 100
- **Result**: Connection pool exhaustion

---

### ❌ Approach 2: Suite-Level Database with Transaction Rollback

**Implementation**:
```swift
@Suite(.dependency(\.defaultDatabase, Database.TestDatabase.withReminderData()))
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        try await db.withRollback { db in
            // All operations here
            // Automatic ROLLBACK at end
        }
    }
}
```

**Why it failed**:
- `withRollback` internally calls `db.write { BEGIN ... }`
- All tests queue behind the **same** `Database.Writer` actor
- Actor serialization creates bottleneck
- **Result**: Tests serialize instead of running in parallel → hangs

**Insight**: The problem wasn't PostgreSQL concurrency—it was Swift actor serialization.

---

### ⚠️ Approach 3: Suite-Level Database with Manual Cleanup

**Implementation**:
```swift
@Suite(.dependency(\.defaultDatabase, Database.TestDatabase.withReminderData()))
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func selectAll() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)
    }
}
```

**For mutation tests**:
```swift
@Test func insertBasicDraft() async throws {
    let inserted = try await db.write { db in
        try await Reminder.insert { ... }.returning(\.self).fetchAll(db)
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

**Status**:
- ✅ Tests pass individually
- ✅ Tests pass sequentially
- ❌ **Tests hang with cmd+U (parallel execution)**
- ⚠️ Pattern matches upstream but still has bottleneck

**Root cause**: TestDatabasePool actor coordinating database creation became bottleneck during parallel suite initialization.

---

### ✅ Approach 4: Direct Database Creation (FINAL SOLUTION)

**Implementation**:
```swift
/// Actor to manage database creation bypassing pool
private actor DatabaseManager {
    private var database: Database.TestDatabase?

    func getDatabase() async throws -> Database.TestDatabase {
        if let database = database {
            return database
        }

        // Create database directly without going through pool actor
        let newDatabase = try await Database.testDatabase(
            configuration: nil,
            prefix: "test"
        )

        // Setup schema
        try await newDatabase.createReminderSchema()
        try await newDatabase.insertReminderSampleData()

        self.database = newDatabase
        return newDatabase
    }
}

public final class LazyTestDatabase: Database.Writer {
    private let manager: DatabaseManager

    init(setupMode: SetupMode, preWarm: Bool = true) {
        self.manager = DatabaseManager(setupMode: setupMode.databaseSetupMode)

        // Pre-warm to prevent thundering herd
        if preWarm {
            Task.detached { [manager] in
                _ = try? await manager.getDatabase()
            }
        }
    }
}
```

**Usage**:
```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func selectAll() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)
    }
}
```

**Why it works**:
1. **Bypasses actor bottleneck**: Each suite's `DatabaseManager` creates database directly, not through shared pool
2. **Parallel initialization**: Multiple suites can create databases concurrently
3. **Pre-warming**: `Task.detached` starts creation in background before first test runs
4. **Isolated schemas**: Each database gets its own PostgreSQL schema
5. **Lazy evaluation**: Database created once per suite, cached in manager
6. **Clean lifecycle**: Automatic cleanup via `deinit`

**Architecture**:
```
Suite 1 → DatabaseManager #1 → Database.testDatabase() → PostgreSQL
Suite 2 → DatabaseManager #2 → Database.testDatabase() → PostgreSQL
Suite 3 → DatabaseManager #3 → Database.testDatabase() → PostgreSQL
Suite 4 → DatabaseManager #4 → Database.testDatabase() → PostgreSQL
```

**Result**:
- ✅ **All 94 tests pass with cmd+U**
- ✅ True parallel execution
- ✅ No actor bottleneck
- ✅ Fast and reliable

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

```swift
enum TestDatabaseSetupMode {
    case empty                     // No tables
    case withSchema                // User/Post schema
    case withSampleData            // User/Post + data
    case withReminderSchema        // Reminder schema (upstream-aligned)
    case withReminderData          // Reminder + data (upstream-aligned)
}
```

**Factory Methods**:
```swift
Database.TestDatabase.withSchema()        // User/Post tables only
Database.TestDatabase.withSampleData()    // User/Post + sample data
Database.TestDatabase.withReminderSchema() // Reminder tables only
Database.TestDatabase.withReminderData()   // Reminder + sample data (most common)
```

### Test Pattern

**Read-Only Tests**:
```swift
@Suite(
    "My Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
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

**Reminder Schema** (matches upstream):
- 2 RemindersList records (Home, Work)
- 2 User records (Alice, Bob)
- 6 Reminder records
- 4 Tag records with relationships

**User/Post Schema** (swift-records-specific):
- 2 User records (Alice, Bob)
- 2 Post records
- 1 Comment record
- 2 Tag records with relationships

---

## Best Practices

### 1. Choose the Right Setup Mode

**For upstream-aligned tests**:
```swift
.dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
```

**For swift-records-specific tests**:
```swift
.dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
```

**For custom schema tests**:
```swift
.dependency(\.defaultDatabase, Database.TestDatabase.withSchema())
// Then create your own schema in test
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

### 5. Test Organization

**By operation type**:
- `SelectExecutionTests.swift` - SELECT operations
- `InsertExecutionTests.swift` - INSERT operations
- `UpdateExecutionTests.swift` - UPDATE operations
- `DeleteExecutionTests.swift` - DELETE operations

**By feature**:
- `TransactionTests.swift` - Transaction management
- `MigrationTests.swift` - Schema migrations
- `PostgresJSONBTests.swift` - JSONB operations

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
| **Direct creation** | ~200ms × 4 | ✅ | **None** | Manual | ✅ **Works!** |

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

### After (Direct Creation)
```swift
@Suite(
    "My Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
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

**Likely Cause**: Actor bottleneck (old pattern)

**Solution**: Ensure using `Database.TestDatabase.withReminderData()` which creates `LazyTestDatabase` with direct database creation

### Connection Pool Exhausted

**Symptom**: `PSQLError` about max connections

**Likely Cause**: Too many concurrent database instances

**Solution**: Share database at suite level, not per-test

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

- `DEVELOPMENT_HISTORY.md` - How we got here
- `PARALLEL_TEST_DEBUGGING.md` - Detailed analysis of the parallel execution problem
- `README.md` - Package overview

---

## Summary

**The key insight**: Don't fight PostgreSQL's concurrency model or Swift's actor model. Give each suite its own database creation path, bypass shared coordination points, and let PostgreSQL do what it does best—handle concurrent transactions.

This architecture:
- ✅ Passes cmd+U (parallel execution)
- ✅ Leverages PostgreSQL strengths
- ✅ Matches real-world patterns
- ✅ Provides clean test isolation
- ✅ Delivers fast, reliable tests

**Status**: ✅ Production-ready with 94 passing tests
