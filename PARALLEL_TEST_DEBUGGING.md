# Parallel Test Execution Debugging

**Date**: 2025-10-08
**Status**: 🔴 Issue persists - Tests pass individually but hang with cmd+U

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

We've successfully:
- ✅ Analyzed upstream patterns (sqlite-data, swift-structured-queries)
- ✅ Removed transaction rollback wrappers (actor bottleneck)
- ✅ Implemented manual cleanup pattern
- ✅ Made tests pass individually

We're stuck on:
- ❌ **Parallel execution (cmd+U) still hangs**
- ❓ Root cause unclear despite following upstream patterns
- ❓ Tests should work with PostgreSQL MVCC but don't

**The core mystery**: Tests follow upstream patterns, have actor isolation, pass individually, yet hang in parallel. Something about our PostgreSQL setup or test database initialization is not concurrency-safe, but it's not obvious what.
