# Parallel Test Execution Debugging

**Date**: 2025-10-08
**Status**: ✅ SOLVED - Tests now pass with cmd+U using direct database creation

## The Problem

### Symptoms
- **Individual execution**: All test suites pass when run one after another
- **Parallel execution (cmd+U)**: Tests hang with spinners, never complete
- **Business requirement**: "cmd+U always passes" - tests must work with Xcode's parallel execution

### Test Suites Affected
1. **SelectExecutionTests.swift** (19 tests) - Read-only operations
2. **InsertExecutionTests.swift** (10 tests) - Insert with cleanup
3. **DeleteExecutionTests.swift** (9 tests) - Delete operations
4. **ExecutionUpdateTests.swift** (8 tests) - Update operations

**Total**: 44 tests across 4 suites

## Upstream Pattern Analysis

### swift-structured-queries Pattern

**Location**: `/Users/coen/Developer/pointfreeco/swift-structured-queries`

**Key Observations**:
```swift
@Suite(.dependency(\.defaultDatabase, try .default()))
struct MyTests {
    @Dependency(\.defaultDatabase) var database

    @Test
    func myTest() async throws {
        // Direct database operations
        try await database.write { db in
            try Record.insert { ... }.execute(db)
        }
    }
}
```

**Characteristics**:
- ✅ Suite-level shared database
- ✅ No transaction wrappers (no `withRollback`)
- ✅ Direct `db.read { }` and `db.write { }` calls
- ✅ Manual cleanup with `Record.delete().execute(db)`
- ✅ SQLite in-memory (instant setup)
- ⚠️ `.serialized` ONLY for SnapshotTests

### sqlite-data Pattern

**Location**: `/Users/coen/Developer/pointfreeco/sqlite-data`

**Key Observations**:
```swift
@Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
    @Dependency(\.defaultDatabase) var database

    @Test
    func test() async throws {
        // Cleanup first
        try await database.write { db in
            try Record.delete().execute(db)
        }
        // Test operations
        try await database.write { db in
            try Record.insert { ... }.execute(db)
        }
    }
}
```

**Characteristics**:
- ✅ Suite-level shared database
- ✅ No `.serialized` trait
- ✅ No transaction wrappers
- ✅ Tests mutate shared state
- ✅ Manual cleanup per test
- ✅ SQLite in-memory

### Key Insight from Upstream
Both upstream packages use:
1. **One database instance per suite** (not per test)
2. **No transaction rollback for isolation**
3. **SQLite handles concurrency naturally** via its serialization model
4. **Manual test data management**

## Approaches Tried

### ❌ Approach 1: Per-Test Database Instances

**Implementation**:
```swift
@Suite("My Tests", .dependency(\.envVars, .development))
struct MyTests {
    @Test(
        "My test",
        .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
    )
    func myTest() async throws {
        @Dependency(\.defaultDatabase) var db
        // Test operations
    }
}
```

**Why it failed**:
- Each test created its own `Database.Writer` actor
- Each actor had its own connection pool (5 connections)
- With 44 parallel tests: 44 × 5 = 220 connections
- PostgreSQL max connections: 100
- **Result**: Connection pool exhaustion

**Verdict**: ❌ Does not scale, wrong pattern for PostgreSQL

---

### ❌ Approach 2: Suite-Level Database with Transaction Rollback

**Implementation**:
```swift
@Suite(
    "My Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test("My test")
    func myTest() async throws {
        try await db.withRollback { db in
            // Test operations - automatically rolled back
        }
    }
}
```

**Why it failed**:
- `withRollback` internally calls `db.write { BEGIN ... }`
- All tests queue behind the **same** `Database.Writer` actor
- Actor serialization creates bottleneck:
  ```
  Test 1: db.withRollback → db.write { BEGIN } → waits for actor
  Test 2: db.withRollback → db.write { BEGIN } → waits for actor
  Test 3: db.withRollback → db.write { BEGIN } → waits for actor
  ```
- **Result**: Tests serialize instead of running in parallel, causing hangs

**Verdict**: ❌ Actor bottleneck prevents parallel execution

---

### ⚠️ Approach 3: Suite-Level Database with Manual Cleanup (CURRENT)

**Implementation**:
```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("SELECT all records")
    func selectAll() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)
    }
}
```

**For mutation tests**:
```swift
@Test("INSERT basic Draft")
func insertBasicDraft() async throws {
    let inserted = try await db.write { db in
        try await Reminder.insert {
            Reminder.Draft(remindersListID: 1, title: "New task")
        }
        .returning(\.self)
        .fetchAll(db)
    }

    #expect(inserted.count == 1)

    // Manual cleanup - matches upstream
    if let id = inserted.first?.id {
        try await db.write { db in
            try await Reminder.find(id).delete().execute(db)
        }
    }
}
```

**Changes Made**:
1. ✅ Removed ALL `withRollback` wrappers (44 instances)
2. ✅ Changed to direct `db.read { }` and `db.write { }` calls
3. ✅ Added manual cleanup after mutations
4. ✅ Used UUIDs for unique test data
5. ✅ Suite-level shared database (one `Database.Writer` per suite)

**Current Status**:
- ✅ Tests pass individually
- ✅ Tests pass when run sequentially
- ❌ **Tests hang with cmd+U (parallel execution)**

**Verdict**: ⚠️ Pattern matches upstream but still hangs in parallel

---

### ✅ Approach 4: Direct Database Creation (SOLUTION)

**Implementation**:
```swift
/// Actor to manage database creation bypassing the pool to avoid actor bottleneck
private actor DatabaseManager {
    private var database: Database.TestDatabase?
    private let setupMode: Database.TestDatabaseSetupMode

    func getDatabase() async throws -> Database.TestDatabase {
        if let database = database {
            return database
        }

        // Create database directly without going through the pool actor
        // This allows parallel test suites to create their databases concurrently
        let newDatabase = try await Database.testDatabase(
            configuration: nil,
            prefix: "test"
        )

        // Setup schema based on mode
        switch setupMode {
        case .withReminderData:
            try await newDatabase.createReminderSchema()
            try await newDatabase.insertReminderSampleData()
        // ... other modes
        }

        self.database = newDatabase
        return newDatabase
    }
}

public final class LazyTestDatabase: Database.Writer {
    private let manager: DatabaseManager

    init(setupMode: SetupMode, preWarm: Bool = true) {
        self.manager = DatabaseManager(setupMode: setupMode.databaseSetupMode)

        // Pre-warm the database by starting acquisition immediately in background
        // This prevents the "thundering herd" problem
        if preWarm {
            Task.detached { [manager] in
                _ = try? await manager.getDatabase()
            }
        }
    }

    public func read<T>(_ block: @Sendable (any Database.Connection) async throws -> T) async throws -> T {
        let database = try await manager.getDatabase()
        return try await database.read(block)
    }

    public func write<T>(_ block: @Sendable (any Database.Connection) async throws -> T) async throws -> T {
        let database = try await manager.getDatabase()
        return try await database.write(block)
    }
}
```

**Usage in tests**:
```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test("SELECT all records")
    func selectAll() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)
    }
}
```

**Why it works**:
1. **Bypasses actor bottleneck**: Each suite's `DatabaseManager` creates its own database directly via `Database.testDatabase()`, not through a shared pool actor
2. **Parallel initialization**: Multiple test suites can create their databases concurrently without queuing
3. **Pre-warming optimization**: `Task.detached` starts database creation in background immediately when suite is initialized, before first test runs
4. **Isolated schemas**: Each database gets its own PostgreSQL schema, preventing data conflicts between parallel tests
5. **Lazy evaluation**: Database is only created once per suite, cached in the `DatabaseManager` actor
6. **Clean lifecycle**: `deinit` ensures database cleanup happens automatically

**Root cause of previous hangs**:
- **Approach 1** (per-test databases): Created 44 actors × 5 connections = 220 connections → exhausted PostgreSQL limit
- **Approach 2** (transaction rollback): All tests queued behind single `Database.Writer` actor → serialization bottleneck
- **Approach 3** (suite-level database): Tests worked individually but TestDatabasePool actor became bottleneck during parallel suite initialization

**The fix**:
- Each suite gets its own `DatabaseManager` actor that creates databases **directly**
- No shared coordination point during initialization = no bottleneck
- Pre-warming prevents thundering herd when first test in suite runs
- Tests pass reliably with cmd+U (Xcode's parallel execution)

**Location**: `Sources/RecordsTestSupport/TestDatabaseHelper.swift:241-289`

**Verdict**: ✅ **SOLVED** - Tests now pass with cmd+U parallel execution

---

## PostgreSQL vs SQLite Differences

### SQLite (Upstream)
| Characteristic | Behavior |
|----------------|----------|
| **Setup time** | Instant (in-memory) |
| **Concurrency model** | Serialized writes, single connection |
| **Per-test database** | Fast enough to create new instance |
| **Transaction overhead** | Minimal |
| **Test isolation** | Via new database or transactions |

### PostgreSQL (Our Implementation)
| Characteristic | Behavior |
|----------------|----------|
| **Setup time** | ~200ms per schema (migrations + seeding) |
| **Concurrency model** | MVCC, multiple connections |
| **Per-test database** | Too slow, exhausts connections |
| **Transaction overhead** | Network round-trips |
| **Test isolation** | Via schemas or transactions |

### Critical Difference
SQLite serializes writes **within the database**, so upstream tests naturally queue.
PostgreSQL handles concurrent writes **natively**, so our tests should run in parallel but are hanging.

## Actor Model Analysis

### Database.Writer Actor Behavior

```swift
public actor Writer {
    func write<T>(_ operation: (Database) async throws -> T) async throws -> T {
        // Actor ensures exclusive access to pool
        // Operations queue behind this actor
    }
}
```

### Current Architecture
```
Suite 1 (SelectExecutionTests) → Database.Writer Actor #1 → PostgreSQL
Suite 2 (InsertExecutionTests) → Database.Writer Actor #2 → PostgreSQL
Suite 3 (DeleteExecutionTests) → Database.Writer Actor #3 → PostgreSQL
Suite 4 (ExecutionUpdateTests) → Database.Writer Actor #4 → PostgreSQL
```

Each suite has its own actor, so they shouldn't interfere... but they still hang.

## Potential Root Causes

### 1. PostgreSQL Connection Pool Saturation
- **Hypothesis**: Even with 4 suites × 5 connections = 20 connections, something exhausts the pool
- **Evidence**: Tests pass individually (1 suite at a time)
- **Test**: Need to monitor actual PostgreSQL connections during cmd+U

### 2. Database Setup Race Condition
- **Hypothesis**: `Database.TestDatabase.withReminderData()` might not be safe for concurrent execution
- **Evidence**: Setup involves migrations + seeding
- **Test**: Need to check if multiple suites call setup simultaneously

### 3. Actor Deadlock
- **Hypothesis**: Some operation awaits another actor that's waiting on the first
- **Evidence**: Tests hang (don't fail, just wait)
- **Test**: Need execution trace of actor interactions

### 4. PostgreSQL Lock Contention
- **Hypothesis**: Multiple suites accessing same seeded data causes table locks
- **Evidence**: All suites use same seeded data (ids 1-6)
- **Test**: Need PostgreSQL lock monitoring during cmd+U

## Differences from Upstream

| Aspect | Upstream (SQLite) | Our Implementation (PostgreSQL) |
|--------|------------------|--------------------------------|
| **Database type** | SQLite in-memory | PostgreSQL remote |
| **Setup cost** | Near-zero | ~200ms (migrations + seeding) |
| **Concurrency** | Single connection | Connection pool |
| **Isolation** | New database per suite | Shared database, shared data |
| **Cleanup** | Not needed (ephemeral) | Manual cleanup required |
| **Test data** | Re-seeded each time | Shared across parallel tests |

## The Mystery

### Why This Is Confusing

1. **Pattern matches upstream**: We followed sqlite-data and swift-structured-queries exactly
2. **Actor isolation exists**: Each suite has its own `Database.Writer` actor
3. **PostgreSQL handles concurrency**: MVCC should allow parallel transactions
4. **Tests are independent**: Each test manages its own data with unique IDs/titles
5. **Individual tests pass**: No test has internal issues

### Yet: Parallel Execution Hangs

**Something about parallel execution causes deadlock or resource exhaustion that doesn't happen sequentially.**

## Next Steps to Debug

### 1. Monitor PostgreSQL Connections
```bash
# While running cmd+U, check connection count:
psql -U $PGUSER -d $PGDATABASE -c "SELECT count(*) FROM pg_stat_activity WHERE datname = '$PGDATABASE';"
```

### 2. Check for Lock Contention
```bash
# While hanging, check for locks:
psql -U $PGUSER -d $PGDATABASE -c "SELECT * FROM pg_locks WHERE NOT granted;"
```

### 3. Add Logging to Database Setup
```swift
@Dependency(\.defaultDatabase, {
    print("🔵 Setting up database for suite: \(suiteName)")
    let db = Database.TestDatabase.withReminderData()
    print("✅ Database setup complete for suite: \(suiteName)")
    return db
}())
```

### 4. Test with Reduced Parallelism
```bash
# Try with just 2 suites to isolate:
swift test --filter "SelectExecutionTests|InsertExecutionTests" --parallel
```

### 5. Examine Database.TestDatabase Implementation
- Check if `withReminderData()` is safe for concurrent calls
- Verify migrations don't have race conditions
- Ensure connection pool initialization is thread-safe

## Questions to Answer

1. **Is Database.TestDatabase.withReminderData() idempotent and concurrency-safe?**
   - Does it properly handle multiple concurrent calls?
   - Are migrations protected against race conditions?

2. **Do parallel tests actually use separate Database.Writer actors?**
   - Or does dependency injection share the same instance?
   - Need to verify with print statements or IDs

3. **Is PostgreSQL the bottleneck?**
   - Connection limit reached?
   - Lock contention on seeded data?
   - Migration table locks?

4. **Is there a Swift Testing framework limitation?**
   - Does cmd+U behave differently than `swift test --parallel`?
   - Are there hidden serialization points?

## Summary

✅ **PROBLEM SOLVED** - Tests now pass with cmd+U parallel execution!

### Journey to Solution:
1. ✅ Analyzed upstream patterns (sqlite-data, swift-structured-queries)
2. ✅ Removed transaction rollback wrappers (actor bottleneck)
3. ✅ Implemented manual cleanup pattern
4. ✅ Identified TestDatabasePool actor as bottleneck during parallel initialization
5. ✅ **Implemented direct database creation to bypass pool actor**

### Final Solution (Approach 4):
- Each test suite gets its own `DatabaseManager` actor
- Database creation happens **directly** via `Database.testDatabase()`, not through shared pool
- Pre-warming with `Task.detached` prevents thundering herd problem
- Tests execute in parallel without actor serialization bottleneck
- **Result**: All 44 tests across 4 suites pass reliably with cmd+U

### Key Insight:
The issue was never with PostgreSQL concurrency or MVCC. The bottleneck was the **TestDatabasePool actor** coordinating database creation during parallel suite initialization. By having each suite create its database directly, we eliminated the shared coordination point and enabled true parallel execution.
