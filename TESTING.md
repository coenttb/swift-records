# Testing Guide

**Last Updated**: 2025-10-09 (assertQuery Implementation)
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

**For concurrency stress tests (100+ parallel operations)**:

```swift
@Suite(
    "Concurrency Tests",
    .dependencies {
        $0.envVars = .development
        // Use connection pool, not single connection
        $0.defaultDatabase = try await Database.TestDatabase.withConnectionPool(
            setupMode: .withReminderData,
            minConnections: 10,
            maxConnections: 50
        )
    }
)
struct ConcurrencyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func concurrent500Inserts() async throws {
        // All 500 should succeed - they queue for connections
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...500 {
                group.addTask {
                    try await db.write { ... }
                }
            }
            try await group.waitForAll()
        }
    }
}
```

**Key differences**:
- `withReminderData()` → Single connection (for normal tests)
- `withConnectionPool()` → 10-50 connections (for stress tests)

**Common pitfall**: A test with 67% success rate was hiding foreign key violations with `try?`. After removing `try?`, the real error became visible: using `remindersListID=3` when only IDs 1 and 2 existed.

### 6. Resource Pooling Patterns: Lessons from swift-html-to-pdf

**Investigation Date**: 2025-10-09

When investigating cmd+U hanging issues, we explored using `@globalActor` patterns from `swift-html-to-pdf` to share resource pools across test suites and prevent connection exhaustion.

#### The swift-html-to-pdf Pattern

```swift
/// Global shared pool actor ensures only one pool exists across all consumers
@globalActor
private actor WebViewPoolActor {
    static let shared = WebViewPoolActor()
    private var sharedPool: ResourcePool<WKWebViewResource>?

    func getOrCreatePool(
        provider: @escaping @Sendable () async throws -> ResourcePool<WKWebViewResource>
    ) async throws -> ResourcePool<WKWebViewResource> {
        if let existing = sharedPool {
            return existing
        }
        let newPool = try await provider()
        sharedPool = newPool
        return newPool
    }
}
```

**Why it works for WebViews**:
- ✅ **WebViews are stateless** - Can be safely reused across different rendering tasks
- ✅ **No data pollution** - Each render is independent
- ✅ **Resource sharing is safe** - Multiple tasks can share the same WebView pool
- ✅ **Prevents resource exhaustion** - One shared pool instead of many

#### Why @globalActor Fails for Databases

**Problem: Data Pollution**

When we applied this pattern to test databases:

```swift
@globalActor
private actor TestDatabasePoolActor {
    static let shared = TestDatabasePoolActor()
    private var sharedPools: [String: ResourcePool<Database.TestDatabase>] = [:]

    func getOrCreatePool(key: String, provider: ...) async throws -> ResourcePool<...> {
        if let existing = sharedPools[key] {
            return existing  // ❌ WRONG: Multiple suites share same database!
        }
        // ...
    }
}
```

**What happened**:
1. Suite A with `.withReminderData()` gets pool key `"reminderData_1_nil_nil"`
2. Suite B also with `.withReminderData()` gets **THE SAME pool** (same key)
3. Suite A deletes some records in tests
4. Suite B checks out the same database and sees Suite A's modifications
5. Tests fail: `Expectation failed: (deleted?.id → nil) == (id → 7)`

**Actual test failure**:
```
􀢄 Test "DELETE with RETURNING" recorded an issue at DeleteExecutionTests.swift:69:9:
   Expectation failed: (deleted?.id → nil) == (id → 7)
􀢄 Test "DELETE with RETURNING" recorded an issue at DeleteExecutionTests.swift:70:9:
   Expectation failed: (deleted?.title → nil) == "Haircut test"
```

The database record was already deleted by another suite sharing the same pool!

#### Key Insight: Stateful vs Stateless Resources

| Aspect | WebViews (Stateless) | Databases (Stateful) |
|--------|---------------------|---------------------|
| **Reusability** | ✅ Can be safely reused | ❌ Cannot be shared between suites |
| **Data Isolation** | N/A (no persistent state) | ✅ **Critical requirement** |
| **Sharing Pattern** | `@globalActor` perfect | ❌ `@globalActor` causes pollution |
| **Resource Exhaustion** | Solved by sharing | **Must solve differently** |

#### The Correct Solution: Reduced Connection Limits

Instead of sharing databases (which causes data pollution), we **reduce per-suite connection limits**:

```swift
public static func withConnectionPool(
    setupMode: LazyTestDatabase.SetupMode,
    minConnections: Int = 5,    // Reduced from 10
    maxConnections: Int = 20    // Reduced from 50
) async throws -> LazyTestDatabase {
    try await LazyTestDatabase(
        setupMode: setupMode,
        capacity: 1,
        warmup: true,
        minConnections: minConnections,
        maxConnections: maxConnections
    )
}
```

**Why this works**:
- Each test suite gets **its own isolated database** (no data pollution)
- Each database has **reduced connection pool** (5-20 instead of 10-50)
- PostgreSQL can handle ~13 suites × 20 connections = 260 connections (within default 400 limit)
- Tests maintain data isolation while avoiding connection exhaustion

#### Comparison

**@globalActor Approach (swift-html-to-pdf)**:
```
All Suites → Shared WebView Pool (capacity=5, maxConnections=50)
    ├─> WebView #1 ✅ Stateless, safe to share
    ├─> WebView #2 ✅ Stateless, safe to share
    └─> WebView #3 ✅ Stateless, safe to share
```

**Isolated Databases Approach (swift-records)**:
```
Suite 1 → Database Pool #1 (capacity=1, maxConnections=20)
Suite 2 → Database Pool #2 (capacity=1, maxConnections=20)
Suite 3 → Database Pool #3 (capacity=1, maxConnections=20)
    ├─> Each suite has isolated data ✅
    ├─> Total connections manageable ✅
    └─> No actor bottleneck ✅
```

#### Results

**With @globalActor (Data Pollution)**:
- ❌ DeleteExecutionTests: 8 of 9 tests failed
- ❌ Data missing from shared database
- ❌ Unpredictable test failures
- ✅ No connection exhaustion

**With Isolated Databases + Reduced Connections**:
- ✅ DeleteExecutionTests: All 9 tests passed
- ✅ Complete data isolation
- ✅ Predictable test behavior
- ⚠️ cmd+U still has some hanging issues (under investigation)

#### Lessons Learned

1. **@globalActor is powerful for stateless resources** - Works perfectly for WebViews, cache pools, etc.
2. **Stateful resources need isolation** - Databases, file handles, etc. cannot be safely shared
3. **Connection limits are the real constraint** - Solve exhaustion by reducing per-suite connections, not sharing databases
4. **Data isolation is non-negotiable** - Test reliability depends on isolated state
5. **Learn from patterns but adapt for context** - swift-html-to-pdf taught us the pattern, but we needed a different solution

#### Current Status

**Individual Suites**: ✅ All pass with proper data isolation
**cmd+U (All Suites)**: ⚠️ Still investigating occasional hangs
**Connection Management**: ✅ Reduced limits prevent exhaustion
**Data Isolation**: ✅ Each suite has its own database

**Resolution** (2025-10-09):
- ✅ Reduced connection limits to 2 min / 10 max per suite
- ✅ cmd+U now completes successfully: **127 tests in 19 suites passed after 1.004 seconds**
- ✅ 13 suites × 10 max connections = 130 connections (well within PostgreSQL's 400 default limit)

### 7. Connection Monitoring and Debugging

**Added**: 2025-10-09 (After resolving cmd+U hanging with reduced connection limits)

#### Overview

Connection management is critical for test reliability. This section covers how to monitor, debug, and troubleshoot connection-related issues during test execution.

#### PostgreSQL Connection Limits

**Default Configuration**:
```sql
-- PostgreSQL default max connections: 400
SHOW max_connections;  -- Usually 100-400 depending on installation

-- Current active connections
SELECT count(*) FROM pg_stat_activity;
```

**Our Test Architecture**:
- **Per-Suite Connections**: Each test suite gets its own database with connection pool
- **Default Limits**: 2 min / 10 max connections per suite
- **Total Capacity**: 13 test suites × 10 max = **130 connections** (33% of PostgreSQL's 400 limit)
- **Safety Margin**: 270 connections available for other services

#### Monitoring Active Connections

**During Test Runs**:

```sql
-- Count connections by state
SELECT
    state,
    count(*) as connection_count
FROM pg_stat_activity
WHERE datname = 'postgres'  -- Your test database name
GROUP BY state
ORDER BY connection_count DESC;
```

**Expected Output** (during cmd+U):
```
     state      | connection_count
----------------+-----------------
 active         |             15
 idle           |             95
 idle in trans. |             10
 (3 rows)
```

**Connection States**:
- `active` - Currently executing a query
- `idle` - Connected but not running a query
- `idle in transaction` - In a transaction but not executing
- `idle in transaction (aborted)` - Transaction failed but not rolled back

#### Detailed Connection Inspection

**Show all active queries**:
```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    state_change,
    wait_event_type,
    wait_event,
    left(query, 50) as query_preview
FROM pg_stat_activity
WHERE datname = 'postgres'
  AND state != 'idle'
ORDER BY query_start;
```

**Find long-running connections**:
```sql
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    state,
    left(query, 100) as query_preview
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - pg_stat_activity.query_start > interval '10 seconds'
ORDER BY duration DESC;
```

**Kill a stuck connection** (emergency only):
```sql
-- Terminate specific connection
SELECT pg_terminate_backend(12345);  -- Replace with actual pid

-- Kill all connections to test database (DANGEROUS)
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE datname = 'postgres'
  AND pid <> pg_backend_pid();
```

#### Connection Pool Diagnostics

**From Test Code**:

```swift
import RecordsTestSupport

@Test func debugConnectionPool() async throws {
    @Dependency(\.defaultDatabase) var db

    // For LazyTestDatabase instances
    if let lazyDB = db as? LazyTestDatabase {
        // Get pool statistics
        let stats = await lazyDB.statistics
        print("""
        Pool Statistics:
          Available: \(stats.available)
          Leased: \(stats.leased)
          Capacity: \(stats.capacity)
          Queue Depth: \(stats.waitQueueDepth)
          Utilization: \(String(format: "%.1f%%", stats.utilization * 100))
        """)

        // Get detailed metrics
        let metrics = await lazyDB.metrics
        print("""
        Pool Metrics:
          Total Handoffs: \(metrics.totalHandoffs)
          Direct Handoffs: \(metrics.directHandoffs)
          Queue Handoffs: \(metrics.queueHandoffs)
          Avg Wait Time: \(metrics.averageWaitTime)ms
          Max Wait Time: \(metrics.maxWaitTime)ms
        """)
    }
}
```

**Interpreting Statistics**:

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| **Utilization** | < 70% | 70-90% | > 90% |
| **Queue Depth** | 0-2 | 3-10 | > 10 |
| **Wait Time** | < 100ms | 100-500ms | > 500ms |
| **Direct Handoffs** | > 80% | 50-80% | < 50% |

**Example Healthy Output**:
```
Pool Statistics:
  Available: 7
  Leased: 3
  Capacity: 10
  Queue Depth: 0
  Utilization: 30.0%

Pool Metrics:
  Total Handoffs: 127
  Direct Handoffs: 122 (96%)
  Queue Handoffs: 5 (4%)
  Avg Wait Time: 12ms
  Max Wait Time: 45ms
```

**Example Unhealthy Output**:
```
Pool Statistics:
  Available: 0
  Leased: 10
  Capacity: 10
  Queue Depth: 15  ⚠️ Tests waiting!
  Utilization: 100.0%  ⚠️ Pool exhausted!

Pool Metrics:
  Total Handoffs: 500
  Direct Handoffs: 50 (10%)  ⚠️ Poor!
  Queue Handoffs: 450 (90%)  ⚠️ Always queuing!
  Avg Wait Time: 450ms  ⚠️ Slow!
  Max Wait Time: 2000ms  ⚠️ Very slow!
```

#### Debugging Hanging Tests

**Symptoms**:
1. `cmd+U` runs but never completes
2. Spinning test indicators in Xcode
3. No output or progress after certain point
4. CPU usage low (not actually running queries)

**Diagnostic Steps**:

**1. Check Connection Exhaustion**:
```bash
# While tests are hanging, run:
psql postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
```

If you see many `idle in transaction` or total connections near PostgreSQL limit:
- ✅ **Connection exhaustion confirmed**
- Solution: Reduce per-suite connection limits further

**2. Check for Connection Leaks**:
```bash
# Monitor connections over time
while true; do
    psql postgres -c "SELECT count(*) FROM pg_stat_activity;"
    sleep 2
done
```

If connections keep increasing without decreasing:
- ✅ **Connection leak confirmed**
- Solution: Audit tests for proper cleanup, check for unclosed transactions

**3. Check for Deadlocks**:
```sql
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

If results show deadlocks:
- ✅ **Deadlock confirmed**
- Solution: Review transaction isolation levels, check for circular dependencies

**4. Check Test Suite Initialization**:

Add logging to suite initialization:
```swift
@Suite(
    "My Tests",
    .dependencies {
        print("🔧 Initializing database for My Tests...")
        $0.envVars = .development
        $0.defaultDatabase = try await Database.TestDatabase.withReminderData()
        print("✅ Database initialized for My Tests")
    }
)
struct MyTests {
    @Test func myTest() async throws {
        print("🧪 Running myTest")
        // ...
        print("✅ myTest completed")
    }
}
```

If initialization never completes:
- ✅ **Initialization bottleneck confirmed**
- Solution: Check database creation, schema setup, or ResourcePool initialization

#### Connection Limit Tuning

**Current Configuration** (as of 2025-10-09):
```swift
public static func withConnectionPool(
    setupMode: LazyTestDatabase.SetupMode,
    minConnections: Int = 2,    // Reduced from 5, originally 10
    maxConnections: Int = 10    // Reduced from 20, originally 50
) async throws -> LazyTestDatabase
```

**When to Adjust**:

**Increase limits** if:
- ✅ All tests pass with current limits
- ✅ Adding more concurrency stress tests
- ✅ Pool utilization consistently > 90%
- ✅ Tests queuing frequently but not hanging

**Decrease limits** if:
- ❌ cmd+U hangs or times out
- ❌ Connection exhaustion errors
- ❌ Total connections approaching PostgreSQL max
- ❌ Multiple test suites competing for connections

**Tuning Formula**:
```
Max Total Connections = (Number of Suites) × (Max Connections per Suite)
                      = 13 × 10
                      = 130 connections

Safe limit: < 70% of PostgreSQL max_connections (280 for default 400)
```

**Example Configurations**:

| Scenario | Min | Max | Total | Use Case |
|----------|-----|-----|-------|----------|
| **Minimal** | 1 | 3 | 39 | Single developer, many test suites |
| **Conservative** | 2 | 10 | 130 | **Current default** - Balanced |
| **Aggressive** | 5 | 20 | 260 | CI with dedicated PostgreSQL |
| **Stress Testing** | 10 | 50 | 650 | Single suite stress test (exceeds limit!) |

**For Concurrency Stress Tests Only**:
```swift
@Suite(
    "Concurrency Stress Tests",
    .disabled(),  // Enable manually for stress testing
    .serialized,  // Run serially to avoid overwhelming other suites
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = try await Database.TestDatabase.withConnectionPool(
            setupMode: .withReminderData,
            minConnections: 10,  // Higher for stress test
            maxConnections: 50   // Much higher for 500+ parallel operations
        )
    }
)
```

#### Emergency Recovery

**If tests hang completely**:

1. **Kill xcodebuild process**:
```bash
pkill -9 xcodebuild
```

2. **Kill all test connections**:
```sql
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE datname = 'postgres'
  AND application_name LIKE '%swift-test%'
  AND pid <> pg_backend_pid();
```

3. **Check for orphaned schemas**:
```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name LIKE 'test_%'
ORDER BY schema_name;
```

4. **Clean up test schemas** (if needed):
```sql
DO $$
DECLARE
    schema_name text;
BEGIN
    FOR schema_name IN
        SELECT nspname FROM pg_namespace WHERE nspname LIKE 'test_%'
    LOOP
        EXECUTE 'DROP SCHEMA ' || quote_ident(schema_name) || ' CASCADE';
    END LOOP;
END $$;
```

#### Best Practices

1. **Monitor During Development**:
   - Run `watch -n 2 'psql postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state"'` in separate terminal
   - Watch for connection count trends
   - Verify connections are released after tests complete

2. **Test Connection Cleanup**:
   ```swift
   @Test func verifyConnectionCleanup() async throws {
       @Dependency(\.defaultDatabase) var db

       // Get initial count
       let initialStats = await (db as? LazyTestDatabase)?.statistics

       // Run operations
       try await db.write { db in
           try await Reminder.insert { ... }.execute(db)
       }

       // Verify connections released
       let finalStats = await (db as? LazyTestDatabase)?.statistics
       #expect(finalStats.leased == initialStats.leased)
   }
   ```

3. **Use Appropriate Limits**:
   - Default (2/10) for normal test suites
   - Increased (10/50) only for stress tests
   - Never exceed 70% of PostgreSQL max_connections in total

4. **Add Timeouts**:
   ```swift
   @Test(.timeLimit(.minutes(1)))
   func myTest() async throws {
       // Test must complete within 1 minute or fail
   }
   ```

5. **Isolate Heavy Tests**:
   ```swift
   @Suite(
       "Heavy Operations",
       .serialized  // Don't run in parallel with other suites
   )
   struct HeavyTests { }
   ```

#### Current Status (2025-10-09)

✅ **All tests passing with cmd+U**
- 127 tests across 19 suites
- Complete in ~1 second
- Connection limits: 2 min / 10 max per suite
- Total peak usage: ~130 connections (33% of PostgreSQL limit)

**Performance Metrics**:
```
Test run with 127 tests in 19 suites passed after 1.004 seconds.
** TEST SUCCEEDED **
```

**Connection Health**:
- No exhaustion
- No hanging
- No leaks
- Proper cleanup

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

**Status**: ✅ Production-Ready (2025-10-09)

### Overview

`assertQuery` is an end-to-end async snapshot testing helper for PostgreSQL statements. It enables comprehensive testing by capturing and verifying both:

1. **SQL Generation** - The exact SQL produced by the query builder
2. **Execution Results** - The data returned from PostgreSQL, formatted as ASCII tables

This matches upstream's `sqlite-data` testing patterns but adapted for PostgreSQL's async execution model.

### Architecture

**Two-Layer Design**:

```
┌─────────────────────────────────────────────────────────┐
│ Tests/RecordsTests/Support/AssertQuery.swift            │
│ Convenience wrapper with auto-injected DB dependency    │
└──────────────────────┬──────────────────────────────────┘
                       │ calls
┌──────────────────────▼──────────────────────────────────┐
│ Sources/RecordsTestSupport/AssertQuery.swift            │
│ Core implementation with explicit execute closure       │
└──────────────────────┬──────────────────────────────────┘
                       │ uses
┌──────────────────────▼──────────────────────────────────┐
│ InlineSnapshotTesting library                           │
│ Handles snapshot recording, comparison, and updates     │
└─────────────────────────────────────────────────────────┘
```

**Layer 1: RecordsTestSupport (Core)**
- Generic, reusable implementation
- Requires explicit `execute:` closure
- Suitable for external packages
- Database-agnostic design

**Layer 2: Test Wrapper (Convenience)**
- Auto-injects `@Dependency(\.defaultDatabase)`
- Clean syntax matching upstream
- Internal to swift-records tests
- Opinionated for our test patterns

### Basic Usage

**Convenience Wrapper** (Recommended):

```swift
@Suite(
  "My Tests",
  .snapshots(record: .never),
  .dependencies {
    $0.envVars = .development
    $0.defaultDatabase = try await Database.TestDatabase.withReminderData()
  }
)
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

**Explicit Execute** (Full Control):

```swift
@Test func selectWithExplicitExecute() async {
  @Dependency(\.defaultDatabase) var db

  await RecordsTestSupport.assertQuery(
    Reminder.select { $0.title }.order(by: \.title).limit(3),
    execute: { statement in
      try await db.read { db in
        try await db.fetchAll(statement)
      }
    },
    sql: {
      """
      SELECT "reminders"."title"
      FROM "reminders"
      ORDER BY "reminders"."title"
      LIMIT 3
      """
    },
    results: {
      """
      ┌─────────────────┐
      │ "Finish report" │
      │ "Groceries"     │
      │ "Haircut"       │
      └─────────────────┘
      """
    }
  )
}
```

### Advanced Features

#### Parameter Pack Support

`assertQuery` handles complex tuple types using Swift's parameter pack feature:

```swift
// Multi-column SELECT with tuple results
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

**Implementation**: Parameter pack overloads added to:
- `Database.Connection.Protocol.fetchAll<each V: QueryRepresentable>(...)`
- `Database.Connection.fetchAll<each V: QueryRepresentable>(...)`
- `Statement.fetchAll<each V: QueryRepresentable>(...)`

#### Swift 6 Concurrency

All signatures include proper `Sendable` constraints:

```swift
func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
  _ query: S,
  execute: @Sendable (S) async throws -> [(repeat (each V).QueryOutput)],
  ...
) async where
  repeat each V: Sendable,
  repeat (each V).QueryOutput: Sendable,
  S: Sendable
```

This ensures:
- ✅ Safe concurrent test execution
- ✅ Actor boundary crossing
- ✅ Database dependency capture in closures
- ✅ Strict concurrency mode compliance

### Snapshot Modes

Control snapshot behavior with suite traits:

```swift
// Never record (default for CI)
@Suite(.snapshots(record: .never))

// Always record (update all snapshots)
@Suite(.snapshots(record: .all))

// Record only failed tests (development)
@Suite(.snapshots(record: .failed))

// Record missing snapshots
@Suite(.snapshots(record: .missing))
```

### Implementation Details

#### The fetchAll Overload Problem

**Challenge**: Swift's type system cannot treat `(repeat each V)` as a single `QueryRepresentable` type because tuples don't conform to protocols.

**Error Before Fix**:
```swift
// ❌ Type '(repeat each V)' cannot conform to 'QueryRepresentable'
try await db.fetchAll(statement)
```

**Solution**: Add explicit parameter pack overloads:

```swift
// Original (single type)
func fetchAll<QueryValue: QueryRepresentable>(
    _ statement: some Statement<QueryValue>
) async throws -> [QueryValue.QueryOutput]

// New (parameter pack tuple)
func fetchAll<each V: QueryRepresentable>(
    _ statement: some Statement<(repeat each V)>
) async throws -> [(repeat (each V).QueryOutput)]
```

This pattern mirrors `QueryDecoder.decodeColumns`:
```swift
// Single column
func decodeColumns<T: QueryRepresentable>(_ type: T.Type) -> T.QueryOutput

// Multiple columns (tuple)
func decodeColumns<each T: QueryRepresentable>(
    _ types: (repeat each T).Type
) -> (repeat (each T).QueryOutput)
```

### Comparison to Upstream

| Aspect | sqlite-data | swift-records | Notes |
|--------|-------------|---------------|-------|
| **Function Name** | `assertQuery` | `assertQuery` | ✅ Identical |
| **Execution Model** | Synchronous | **Async** | PostgreSQL requirement |
| **Execute Closure** | `throws` | `async throws` | Async/await |
| **Database Injection** | `@Dependency(\.defaultDatabase)` | `@Dependency(\.defaultDatabase)` | ✅ Identical |
| **Snapshot Library** | InlineSnapshotTesting | InlineSnapshotTesting | ✅ Same |
| **ASCII Tables** | printTable | printTable | ✅ Same format |
| **Parameter Packs** | Supported | Supported | ✅ Same |
| **Result Type** | `[(repeat each V).QueryOutput)]` | `[(repeat each V).QueryOutput)]` | ✅ Identical |

**Key Differences**:
1. **Async execution**: `async throws` instead of `throws`
2. **Database connection**: Uses actor-based `Database.Reader` instead of synchronous SQLite handle
3. **Dependencies trait**: Uses `.dependencies { }` closure instead of `.dependency()` for async setup

### Best Practices

#### 1. Choose the Right Variant

**Use Convenience Wrapper** (most tests):
```swift
await assertQuery(query) { sql } results: { data }
```
- ✅ Clean, readable syntax
- ✅ Matches upstream pattern
- ✅ Auto-injects database
- ❌ Only for internal swift-records tests

**Use Explicit Execute** when:
- Testing external packages that depend on RecordsTestSupport
- Need custom execution logic
- Want explicit control over database access
- Debugging query execution

#### 2. Snapshot Recording Strategy

**Development**:
```swift
@Suite(.snapshots(record: .failed))
```
- Records snapshots when tests fail
- Useful for updating expected outputs
- Good for iterative development

**CI/Production**:
```swift
@Suite(.snapshots(record: .never))
```
- Enforces exact matches
- Prevents accidental snapshot changes
- Ensures reproducible tests

#### 3. Test Organization

Group related assertions in same test:

```swift
@Test func reminderOperations() async {
  // Select
  await assertQuery(Reminder.all) { ... } results: { ... }

  // Filter
  await assertQuery(Reminder.where { $0.isCompleted }) { ... } results: { ... }

  // Order
  await assertQuery(Reminder.order(by: \.title)) { ... } results: { ... }
}
```

#### 4. Complex Queries

For joins and complex selects:

```swift
await assertQuery(
  Reminder
    .join(RemindersList.self, on: { $0.remindersListID == $1.id })
    .select { reminder, list in
      (reminder.title, list.name)
    }
) {
  """
  SELECT "reminders"."title", "reminders_lists"."name"
  FROM "reminders"
  INNER JOIN "reminders_lists" ON "reminders"."remindersListID" = "reminders_lists"."id"
  """
} results: {
  """
  ┌──────────────┬────────┐
  │ "Groceries" │ "Home" │
  │ "Haircut"   │ "Home" │
  └──────────────┴────────┘
  """
}
```

#### 5. Error Testing

Capture and verify error messages:

```swift
await assertQuery(
  User.where { $0.invalidColumn == "test" }
) {
  """
  -- Expected SQL that would cause error
  """
} results: {
  """
  column "invalidColumn" does not exist
  """
}
```

### Snapshot Test Coverage

**Status**: 🟢 Core Patterns Complete (2025-10-09)

#### Current Coverage

**QuerySnapshotTests.swift** (39 tests across 9 suites):

**SELECT Patterns** (10 tests):
- SELECT all columns
- SELECT specific columns
- SELECT multiple columns
- SELECT with WHERE
- SELECT with multiple WHERE
- SELECT with LIMIT/OFFSET
- SELECT DISTINCT
- SELECT with NULL/NOT NULL checks
- SELECT with IN clause

**Comparison Operators** (4 tests):
- Greater than (`>`)
- Greater than or equal (`>=`)
- Less than (`<`)
- Not equal (`!=`)

**Logical Operators** (3 tests):
- AND operator
- OR operator
- NOT operator

**String Operations** (3 tests):
- `hasPrefix()` → `LIKE 'prefix%'`
- `hasSuffix()` → `LIKE '%suffix'`
- `contains()` → `LIKE '%substring%'`

**Aggregate Functions** (3 tests):
- COUNT all
- COUNT with WHERE
- COUNT DISTINCT

**INSERT Patterns** (6 tests - SQL generation only):
- INSERT single Draft record
- INSERT multiple Draft records
- INSERT with RETURNING
- INSERT with NULL optional fields
- INSERT with enum value
- INSERT with boolean fields

**UPDATE Patterns** (5 tests - SQL generation only):
- UPDATE single column with WHERE
- UPDATE multiple columns
- UPDATE with RETURNING
- UPDATE with NULL value
- UPDATE with complex WHERE

**DELETE Patterns** (5 tests - SQL generation only):
- DELETE with WHERE clause
- DELETE with RETURNING
- DELETE with complex WHERE
- DELETE using find()
- DELETE using find() with sequence

**Test Results**:
```
Test run with 39 tests in 9 suites passed after 0.282 seconds.
** TEST SUCCEEDED **
```

#### Comparison to Upstream

| Test Category | Upstream | swift-records | Status |
|--------------|----------|---------------|--------|
| **Snapshot Test Files** | 37 files | 1 file | 🟡 3% coverage |
| **assertQuery Usages** | 320+ | 39 | 🟡 12% coverage |
| **SELECT patterns** | ✅ Extensive | ✅ Basic | ⚠️ Need more variations |
| **INSERT patterns** | ✅ Many | ✅ Basic (SQL only) | 🟡 Have core patterns |
| **UPDATE patterns** | ✅ Many | ✅ Basic (SQL only) | 🟡 Have core patterns |
| **DELETE patterns** | ✅ Many | ✅ Basic (SQL only) | 🟡 Have core patterns |
| **JOIN operations** | ✅ All types | ❌ None | 🔴 Missing |
| **Aggregate functions** | ✅ Complete | ⚠️ Basic | 🟡 Need more |
| **WHERE clauses** | ✅ All operators | ⚠️ Basic | 🟡 Need more |
| **CTEs** | ✅ Yes | ❌ None | 🔴 Missing |
| **UNION/INTERSECT** | ✅ Yes | ❌ None | 🔴 Missing |
| **Scalar functions** | ✅ Extensive | ❌ None | 🔴 Missing |

**Overall Parity**: **~12%** (39 of 320+ snapshot tests)

#### Implementation Notes

**INSERT/UPDATE/DELETE Tests**:
- Use `assertInlineSnapshot` with `.sql` format (not full `assertQuery`)
- Reason: `Insert`, `Update`, `Delete` types are not `Sendable` in current implementation
- Trade-off: SQL generation verified, execution not snapshot-tested (covered by execution tests)
- Example:
  ```swift
  assertInlineSnapshot(
    of: Reminder.insert { Draft(...) },
    as: .sql
  ) {
    """
    INSERT INTO "reminders" (...)
    VALUES (...)
    """
  }
  ```

**Priority Matrix**:
- ✅ **Core CRUD patterns**: Complete (39 tests covering SELECT/INSERT/UPDATE/DELETE)
- 🟡 **Advanced SELECT**: In progress (JOINs, aggregates needed)
- ⏳ **Advanced features**: Not started (CTEs, UNION, window functions)

#### Next Steps

**Phase 1: Core Operations** (Priority: High) - ✅ COMPLETE
- ✅ INSERT snapshots (basic, multiple, RETURNING)
- ✅ UPDATE snapshots (single, multiple columns, WHERE conditions)
- ✅ DELETE snapshots (single, WHERE clause, RETURNING)

**Phase 2: Advanced SELECT** (Priority: High)
- [ ] JOIN snapshots (INNER, LEFT, RIGHT, FULL OUTER)
- [ ] Aggregate function snapshots (SUM, AVG, MIN, MAX, GROUP BY)
- [ ] Subquery snapshots (IN, EXISTS, FROM, SELECT)

**Phase 3: Advanced Features** (Priority: Medium)
- [ ] CTE snapshots (WITH clauses, recursive)
- [ ] UNION/INTERSECT/EXCEPT snapshots
- [ ] Window function snapshots
- [ ] Array operations snapshots

**Phase 4: Type System** (Priority: Medium)
- [ ] Selection type snapshots
- [ ] Decoding pattern snapshots
- [ ] Custom type snapshots

**Estimated Effort**: 6-8 weeks for 80% parity

#### Benefits of Comprehensive Snapshot Coverage

1. **SQL Generation Verification**: Catch regressions in query building
2. **PostgreSQL Compatibility**: Ensure generated SQL is valid PostgreSQL
3. **Documentation**: Snapshots serve as executable examples
4. **Confidence**: Safe refactoring of query builder internals
5. **Upstream Alignment**: Match patterns from swift-structured-queries

### Troubleshooting

#### Snapshot Mismatch

**Symptom**: Test fails with diff showing expected vs actual

**Common Causes**:
1. **Data Changed**: Test database has different data than expected
2. **SQL Changed**: Query builder generated different SQL
3. **Whitespace**: Indentation or line ending differences

**Solutions**:
- Use `.snapshots(record: .failed)` to record new snapshot
- Verify test database setup is correct
- Check trailing whitespace in snapshot strings

#### Type Inference Issues

**Symptom**: Compiler can't infer parameter pack types

**Solution**: Add explicit type annotation:

```swift
// ❌ Compiler confused
await assertQuery(query) { ... }

// ✅ Explicit type
await assertQuery<String, Int>(query) { ... }
```

#### Sendable Errors

**Symptom**: `Cannot convert non-Sendable type` errors

**Cause**: Query types or closures crossing actor boundaries

**Solution**: Ensure all types conform to Sendable:
```swift
extension MyType: Sendable {}
```

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
- ✅ Full snapshot testing with assertQuery
- ✅ Parameter pack support for complex queries
- ✅ Swift 6 strict concurrency compliant

**Status**: ✅ Production-ready with comprehensive testing infrastructure
