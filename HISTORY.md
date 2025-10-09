# Development History

**Period**: 2025-10-08
**Summary**: Journey from 50 compilation errors to 94 passing tests

This document chronicles the development milestones that brought swift-records from a broken test suite to production-ready status with comprehensive PostgreSQL testing.

---

## Table of Contents

1. [Phase 1: Test Cleanup](#phase-1-test-cleanup)
2. [Phase 2: Reminder Schema Implementation](#phase-2-reminder-schema-implementation)
3. [Phase 3: Package Deduplication](#phase-3-package-deduplication)
4. [Phase 4: Test Fixes](#phase-4-test-fixes)
5. [Key Learnings](#key-learnings)
6. [2025-10-08: ResourcePool Integration](#2025-10-08-resourcepool-integration)
7. [2025-10-09: Documentation Consolidation](#2025-10-09-documentation-consolidation)
8. [2025-10-08 Early Morning: Parallel Test Debugging Journey](#2025-10-08-early-morning-parallel-test-debugging-journey)
9. [2025-10-08 Morning: Upstream Analysis and Schema Discovery](#2025-10-08-morning-upstream-analysis-and-schema-discovery)
10. [2025-10-08 Afternoon: Upstream Test Pattern Analysis](#2025-10-08-afternoon-upstream-test-pattern-analysis)
11. [2025-10-09 Afternoon: Test Database Simplification](#2025-10-09-afternoon-test-database-simplification)
12. [Historical Reference: Completed Work](#historical-reference-completed-work)

---

## Phase 1: Test Cleanup

**Duration**: ~1 hour
**Status**: ✅ Completed

### Objective
Remove duplicate and obsolete test files to establish clear package boundaries between swift-records and swift-structured-queries-postgres.

### Actions Taken

#### Deleted 17 Files

**SQL Generation Duplicates** (covered in swift-structured-queries-postgres):
- SelectTests.swift, InsertTests.swift, UpdateTests.swift, DeleteTests.swift
- JoinTests.swift, WhereTests.swift, UnionTests.swift
- CommonTableExpressionTests.swift, BindingTests.swift
- OperatorTests.swift, ScalarFunctionsTests.swift (×2)
- AggregateFunctionsTests.swift (×2)
- AdvancedFeaturesTests.swift, SpecificFeaturesTests.swift

**Obsolete Tests**:
- StatementTests.swift (covered by BasicTests.swift)

#### Retained Files

**For Future Activation**:
- ExecutionUpdateTests.swift (commented - needs rewriting)
- ExecutionValuesTests.swift (commented - needs rewriting)
- LiveTests.swift (×2) (commented - needs rewriting)
- QueryDecoderTests.swift (active)

### Critical Discovery: Schema Mismatch

The commented test files expected **upstream Reminder schema** but swift-records only had User/Post schema. This required choosing between:

**Option 1**: Add Reminder Schema (Align with Upstream)
**Option 2**: Rewrite Tests for User/Post Schema
**Option 3**: Hybrid Approach

**Decision**: Chose **Option 1** to maintain upstream alignment and enable test porting from sqlite-data.

### Verification

```bash
xcodebuild build -scheme Records
# ✅ BUILD SUCCEEDED
```

**Outcome**: Reduced from 22 test files to 5, establishing clear package boundaries.

---

## Phase 2: Reminder Schema Implementation

**Duration**: ~2 hours
**Status**: ✅ Completed

### Objective
Implement upstream-aligned Reminder schema and create comprehensive execution tests matching sqlite-data patterns.

### What Was Implemented

#### 1. Reminder Schema Models

**Created**: `Sources/RecordsTestSupport/ReminderSchema.swift`

Upstream-matching models:
- `@Table struct Reminder` - Core reminder with all fields
- `@Table struct RemindersList` - Lists containing reminders
- `@Table struct User` - Simple user model
- `@Table struct Tag` - Tags for categorization
- `@Table struct ReminderTag` - Junction table
- `enum Priority` - Low/Medium/High priority

#### 2. Test Infrastructure

**Updated**: `Sources/RecordsTestSupport/TestDatabaseHelper.swift`

Added factory methods:
```swift
Database.TestDatabase.withSchema()        // User/Post
Database.TestDatabase.withSampleData()    // User/Post + data
Database.TestDatabase.withReminderSchema() // Reminder only
Database.TestDatabase.withReminderData()   // Reminder + data (upstream-aligned)
```

Sample data:
- 2 RemindersList records (Home, Work)
- 2 User records (Alice, Bob)
- 6 Reminder records
- 4 Tag records with relationships

#### 3. Comprehensive Execution Tests

Created 4 new test suites with **49 tests**:

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| SelectExecutionTests.swift | 22 | SELECT, WHERE, JOIN, ORDER BY, LIMIT, aggregates |
| InsertExecutionTests.swift | 9 | INSERT, UPSERT, RETURNING, ON CONFLICT |
| UpdateExecutionTests.swift | 8 | UPDATE with WHERE, RETURNING |
| DeleteExecutionTests.swift | 10 | DELETE, CASCADE, foreign keys |

Full CRUD coverage with edge cases:
- ✅ NULL handling
- ✅ Enum comparisons
- ✅ Foreign key constraints
- ✅ CASCADE deletions
- ✅ Draft insert patterns
- ✅ DISTINCT, GROUP BY, HAVING

### Verification

```bash
xcodebuild build -workspace StructuredQueries.xcworkspace -scheme Records
# ✅ BUILD SUCCEEDED
```

**Outcome**: 49 new execution tests, upstream-aligned schema, dual-schema support (User/Post + Reminder).

---

## Phase 3: Package Deduplication

**Duration**: ~1 hour
**Status**: ✅ Completed

### Objective
Resolve ~500 lines of duplicate query language code causing ambiguous function errors when using swift-records and swift-structured-queries-postgres together.

### The Problem

When swift-structured-queries-postgres was forked, aggregate/scalar functions were removed. swift-records filled the gap by duplicating query language code. After restoring upstream functionality, both packages contained identical extensions → **build ambiguity errors**.

### Architecture Clarification

**swift-structured-queries-postgres** (Query Language):
- SQL query building DSL
- Aggregate/scalar functions
- PostgreSQL-specific syntax
- Statement types
- ❌ NO database connections or execution

**swift-records** (Database Operations):
- Database connection management
- Query execution (.execute(), .fetchAll(), .fetchOne())
- Connection pooling, transactions, migrations
- Test utilities
- ❌ NO query building extensions

### Actions Taken

#### 1. Moved PostgreSQL-Specific Features

**Created**: `swift-structured-queries-postgres/.../PostgreSQLAggregates.swift`
- `arrayAgg()`, `jsonAgg()`, `jsonbAgg()`, `stringAgg()`
- Statistical: `stddev()`, `stddevPop()`, `stddevSamp()`, `variance()`

**Enhanced**: `PostgreSQLFunctions.swift`
- Added `ilike()` operator (case-insensitive LIKE)

#### 2. Deleted Duplicates from swift-records

Removed 6 extension files (~750 lines):
- `QueryExpression.swift` (513 lines) - All aggregate/scalar functions
- `PrimaryKeyedTableDefinition.swift` (26 lines) - Duplicate extension
- `Select.swift` (65 lines) - Duplicate .count() methods
- `Table.swift` (21 lines) - Query building convenience
- `TableColumn.swift` (100 lines) - PostgreSQL aggregates
- `Where.swift` (23 lines) - Duplicate .count() method

**Kept**:
- `Collation.swift` (28 lines) - Legitimate database constants

#### 3. Fixed Database Operations

Updated `Statement+Postgres.swift`:
```swift
// BEFORE (broken)
let query = asSelect().count()

// AFTER (upstream pattern)
let query = asSelect().select { _ in .count() }
```

### Verification

```bash
# Both packages build successfully
xcodebuild -workspace StructuredQueries.xcworkspace \
  -scheme StructuredQueriesPostgres build
# ✅ BUILD SUCCEEDED

xcodebuild -workspace StructuredQueries.xcworkspace \
  -scheme Records build
# ✅ BUILD SUCCEEDED
```

**Outcome**: Clean separation of concerns, ~750 lines of duplicate code removed, zero ambiguity errors.

---

## Phase 4: Test Fixes

**Duration**: ~1 hour
**Status**: ✅ Completed (94/94 tests passing)

### Issue #1: PostgreSQL SERIAL Sequence Not Updated

#### Problem
All 10 INSERT tests failing with PSQLError - primary key conflicts.

#### Root Cause
When inserting with explicit IDs, PostgreSQL doesn't auto-update SERIAL sequences:

```sql
INSERT INTO "reminders" ("id", ...) VALUES (1, ...), (6, ...)
-- Sequence still at 1! Next auto-generated ID = 1 → CONFLICT
```

#### Solution
Reset sequences after explicit inserts using `pg_get_serial_sequence()`:

```swift
try await db.execute("""
    SELECT setval(pg_get_serial_sequence('"reminders"', 'id'),
                  (SELECT MAX(id) FROM "reminders"))
""")
```

**Why `pg_get_serial_sequence()`?**
- Unquoted `users` → sequence `users_id_seq`
- Quoted `"reminders"` → sequence `"reminders_id_seq"` (with quotes!)

**Files Changed**: `TestDatabaseHelper.swift:218-234`

---

### Issue #2: PostgreSQL DATE Type Loses Time Component

#### Problem
Date test failing with ~20-hour difference (not a rounding error).

#### Root Cause
PostgreSQL `DATE` type stores only `YYYY-MM-DD`, not time:

```
Input:  2025-10-09 15:30:45
Stored: 2025-10-09 00:00:00 (midnight!)
```

#### Solution
Compare date components only:

```swift
// OLD (fails for DATE columns)
#expect(abs(dueDate.timeIntervalSince(futureDate)) < 1.0)

// NEW (compares date components only)
let calendar = Calendar.current
let insertedComponents = calendar.dateComponents([.year, .month, .day], from: futureDate)
let retrievedComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
#expect(insertedComponents == retrievedComponents)
```

**PostgreSQL date types**:
- `DATE`: Date only (YYYY-MM-DD)
- `TIMESTAMP`: Date + time
- `TIMESTAMPTZ`: Date + time + timezone

**Files Changed**: `InsertExecutionTests.swift:214-240`

---

### Final Test Results

| Suite | Tests | Status |
|-------|-------|--------|
| SELECT Execution | 19 | ✅ Passing |
| INSERT Execution | 10 | ✅ Passing |
| UPDATE Execution | 8 | ✅ Passing |
| DELETE Execution | 9 | ✅ Passing |
| Draft Insert | 6 | ✅ Passing |
| Transaction Mgmt | 4 | ✅ Passing |
| Database Access | 4 | ✅ Passing |
| Statement Extensions | 7 | ✅ Passing |
| PostgresJSONB | 8 | ✅ Passing |
| Configuration | 5 | ✅ Passing |
| Query Decoder | 5 | ✅ Passing |
| Adapter | 5 | ✅ Passing |
| Trigger | 1 | ✅ Passing |
| Integration | 1 | ✅ Passing |
| Basic | 2 | ✅ Passing |

**Total**: 94 passing, 3 skipped (intentionally)

---

## Key Learnings

### PostgreSQL-Specific Gotchas

1. **SERIAL Sequences**: Don't auto-update with explicit IDs - must call `setval()`
2. **Sequence Naming**: Quoted tables have quoted sequence names - use `pg_get_serial_sequence()`
3. **DATE vs TIMESTAMP**: DATE loses time component - compare dates only
4. **DELETE ORDER BY/LIMIT**: Not supported - use subquery pattern

### Architecture Principles

1. **Clear Package Boundaries**: Query language ≠ Database operations
2. **Upstream Alignment**: Match sqlite-data patterns for familiarity
3. **Dual Schema Support**: User/Post for swift-records tests, Reminder for upstream alignment
4. **Test Isolation**: PostgreSQL schemas provide clean per-suite isolation

### Testing Patterns

1. **Manual Cleanup**: No `withRollback` - explicit cleanup in tests
2. **Suite-Level Database**: One database per suite, not per test
3. **Dependency Injection**: `.dependency(\.defaultDatabase, ...)` pattern
4. **Sample Data**: Realistic, predictable test data

---

## Time Investment

- **Phase 1** (Cleanup): ~1 hour
- **Phase 2** (Schema): ~2 hours
- **Phase 3** (Deduplication): ~1 hour
- **Phase 4** (Fixes): ~1 hour

**Total**: ~5 hours from "50 compilation errors" to "94 passing tests"

---

## Success Metrics

- ✅ **94/94 tests passing** (100% pass rate excluding intentional skips)
- ✅ **Clear package boundaries** established and documented
- ✅ **Upstream alignment** with sqlite-data and swift-structured-queries
- ✅ **~750 lines** of duplicate code removed
- ✅ **Comprehensive CRUD coverage** with PostgreSQL-specific tests
- ✅ **Production-ready** database operations layer

---

**Status**: ✅ READY FOR PRODUCTION

The swift-records package now provides a solid foundation for PostgreSQL database operations with comprehensive test coverage and clean architecture.

---

## 2025-10-08: ResourcePool Integration

### Problem

LazyTestDatabase used simple DatabaseManager actor, causing:
- Thundering herd issues during parallel suite initialization
- Actor serialization bottleneck
- No metrics or observability

### Solution

Integrated swift-resource-pool for professional-grade resource pooling:
- FIFO fairness with direct handoff (eliminates thundering herd)
- Comprehensive metrics (wait times, handoff rates, utilization)
- Sophisticated pre-warming (synchronous first + background remainder)
- Resource validation and cycling capabilities

### Implementation Details

**Added PoolableResource conformance to Database.TestDatabase**:
```swift
extension Database.TestDatabase: PoolableResource {
    public func isStillValid() async -> Bool {
        // Check connection is alive
    }

    public func shutdown() async {
        // Clean up database resources
    }
}
```

**Replaced DatabaseManager with ResourcePool**:
```swift
let pool = try await ResourcePool<Database.TestDatabase>(
    minimumResourceCount: minimumResourceCount,
    maximumResourceCount: maximumResourceCount
) {
    try await Database.testDatabase(setupMode: setupMode)
}
```

**Migrated all test suites to async factory methods**:
```swift
@Suite(
    "My Tests",
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
```

**Added TestMetrics.swift for observability**:
- Resource requests tracking
- Wait time monitoring
- Pool utilization metrics
- Handoff statistics

### Results

- ✅ All tests passing with cmd+U
- ✅ True parallel execution
- ✅ No actor bottleneck
- ✅ Comprehensive metrics available

### Files Modified

- **Package.swift** - Added swift-resource-pool dependency, macOS 14.0 platform
- **TestDatabase+PoolableResource.swift** (NEW) - PoolableResource conformance
- **TestDatabaseHelper.swift** - ResourcePool integration
- **TestMetrics.swift** (NEW) - Observability infrastructure
- **TestDatabase.swift** - Moved TestDatabaseSetupMode enum
- **All 11 test files** - Updated to async .dependencies pattern

### Key Fixes During Integration

1. **MemberImportVisibility handling** - Required explicit imports for ResourcePool
2. **Async dependencies pattern** - Updated to `.dependencies { }` for async support
3. **Swift-dependencies 1.10.0** - Needed for async trait support

---

## 2025-10-09: Documentation Consolidation

### Motivation

Consolidated scattered documentation into 3-file architecture for better maintainability and clarity.

### Changes

**Created**:
- **ARCHITECTURE.md** - Living reference for database operations architecture
- **TESTING.md** - Living guide for testing patterns (moved from docs/TESTING_ARCHITECTURE.md)
- **HISTORY.md** - This file, append-only chronicle (moved from docs/DEVELOPMENT_HISTORY.md)

**Preserved**:
- **docs/archive/** - Historical artifacts unchanged

### Benefits

- ✅ Easy to find current architecture (ARCHITECTURE.md)
- ✅ Easy to find testing patterns (TESTING.md)
- ✅ Historical context preserved (HISTORY.md)
- ✅ Clear separation of concerns
- ✅ Better maintainability

---

## 2025-10-08 Early Morning: Parallel Test Debugging Journey

**Status**: ✅ SOLVED - Tests now pass with cmd+U using direct database creation

### The Problem

**Symptoms**:
- Individual execution: All test suites pass when run one after another
- Parallel execution (cmd+U): Tests hang with spinners, never complete
- Business requirement: "cmd+U always passes" - tests must work with Xcode's parallel execution

**Test Suites Affected**:
1. SelectExecutionTests.swift (19 tests) - Read-only operations
2. InsertExecutionTests.swift (10 tests) - Insert with cleanup
3. DeleteExecutionTests.swift (9 tests) - Delete operations
4. ExecutionUpdateTests.swift (8 tests) - Update operations

**Total**: 44 tests across 4 suites

### Approaches Tried

#### ❌ Approach 1: Per-Test Database Instances

**Implementation**: Each test created its own `Database.Writer` actor with 5-connection pool

**Why it failed**:
- 44 tests × 5 connections = 220 connections
- PostgreSQL max connections: 100
- **Result**: Connection pool exhaustion

**Verdict**: Does not scale, wrong pattern for PostgreSQL

---

#### ❌ Approach 2: Suite-Level Database with Transaction Rollback

**Implementation**: Used `db.withRollback { }` for test isolation

**Why it failed**:
- `withRollback` internally calls `db.write { BEGIN ... }`
- All tests queued behind the **same** `Database.Writer` actor
- Actor serialization created bottleneck:
  ```
  Test 1: db.withRollback → db.write { BEGIN } → waits for actor
  Test 2: db.withRollback → db.write { BEGIN } → waits for actor
  Test 3: db.withRollback → db.write { BEGIN } → waits for actor
  ```
- **Result**: Tests serialized instead of running in parallel

**Verdict**: Actor bottleneck prevents parallel execution

---

#### ⚠️ Approach 3: Suite-Level Database with Manual Cleanup

**Implementation**:
```swift
@Suite(
    "SELECT Execution Tests",
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

**Changes Made**:
1. Removed ALL `withRollback` wrappers (44 instances)
2. Changed to direct `db.read { }` and `db.write { }` calls
3. Added manual cleanup after mutations
4. Suite-level shared database

**Status**:
- ✅ Tests pass individually
- ✅ Tests pass sequentially
- ❌ **Tests hang with cmd+U (parallel execution)**

**Verdict**: Pattern matches upstream but still hangs due to TestDatabasePool actor bottleneck

---

#### ✅ Approach 4: Direct Database Creation (SOLUTION)

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
        let newDatabase = try await Database.testDatabase(
            configuration: nil,
            prefix: "test"
        )

        // Setup schema
        try await setupMode.setup(newDatabase)

        self.database = newDatabase
        return newDatabase
    }
}

public final class LazyTestDatabase: Database.Writer {
    private let manager: DatabaseManager

    init(setupMode: SetupMode, preWarm: Bool = true) {
        self.manager = DatabaseManager(setupMode: setupMode.databaseSetupMode)

        // Pre-warm the database in background
        if preWarm {
            Task.detached { [manager] in
                _ = try? await manager.getDatabase()
            }
        }
    }
}
```

**Why it works**:
1. **Bypasses actor bottleneck**: Each suite's `DatabaseManager` creates database directly via `Database.testDatabase()`
2. **Parallel initialization**: Multiple suites create databases concurrently without queuing
3. **Pre-warming optimization**: `Task.detached` starts creation in background before first test runs
4. **Isolated schemas**: Each database gets its own PostgreSQL schema
5. **Lazy evaluation**: Database created once per suite, cached in `DatabaseManager`

**Root cause of previous hangs**:
- **Approach 1**: 220 connections exhausted PostgreSQL limit
- **Approach 2**: All tests queued behind single `Database.Writer` actor
- **Approach 3**: TestDatabasePool actor became bottleneck during parallel suite initialization

**The fix**:
- Each suite gets own `DatabaseManager` actor that creates databases **directly**
- No shared coordination point = no bottleneck
- Pre-warming prevents thundering herd when first test runs

**Verdict**: ✅ **SOLVED** - Tests pass reliably with cmd+U

### PostgreSQL vs SQLite Differences

| Characteristic | SQLite (Upstream) | PostgreSQL (Our Implementation) |
|----------------|-------------------|--------------------------------|
| Setup time | Instant (in-memory) | ~200ms per schema |
| Concurrency model | Serialized writes | MVCC, multiple connections |
| Per-test database | Fast enough | Too slow, exhausts connections |
| Transaction overhead | Minimal | Network round-trips |
| Test isolation | Via new database or transactions | Via schemas or transactions |

### Key Insight

The issue was never with PostgreSQL concurrency or MVCC. The bottleneck was the **TestDatabasePool actor** coordinating database creation during parallel suite initialization. By having each suite create its database directly, we eliminated the shared coordination point and enabled true parallel execution.

**Location**: `Sources/RecordsTestSupport/TestDatabaseHelper.swift`

---

## 2025-10-08 Morning: Upstream Analysis and Schema Discovery

### Objective

Analyze sqlite-data (SQLite database operations) as the true comparison for swift-records (PostgreSQL database operations).

### Key Discovery: Wrong Schema

**Current State**: swift-records used User/Post/Comment schema
**Upstream State**: sqlite-data and swift-structured-queries use Reminder/RemindersList schema

**Problem**:
- Diverged from upstream without justification
- Made porting tests from upstream harder
- Broke commented test files (expected Reminder, found User)
- No alignment with Point-Free ecosystem

### Package Hierarchy Clarification

```
swift-structured-queries (query language)
├── SQLite variant → _StructuredQueriesSQLite
│   └── Used by: sqlite-data
└── PostgreSQL variant → StructuredQueriesPostgres
    └── Used by: swift-records
```

### Direct Comparison

| Aspect | sqlite-data (SQLite) | swift-records (PostgreSQL) |
|--------|---------------------|---------------------------|
| Purpose | Database operations | Database operations |
| Query Language | swift-structured-queries | swift-structured-queries-postgres |
| Test Schema | ✅ Reminder, RemindersList | ❌ User, Post (WRONG) |
| assertQuery() | ✅ Active | ❌ Commented out |
| Dependency Injection | ✅ `.dependency(\.defaultDatabase, ...)` | ✅ Has it |
| Test Database | Throwaway SQLite (in-memory) | PostgreSQL schemas |

### Upstream Test Schema

**From sqlite-data Tests/SQLiteDataTests/Internal/Schema.swift**:

```swift
@Table struct Reminder: Equatable, Identifiable {
  let id: Int
  var dueDate: Date?
  var isCompleted = false
  var priority: Int?
  var title = ""
  var remindersListID: RemindersList.ID
}

@Table struct RemindersList: Equatable, Identifiable {
  let id: Int
  var title = ""
}

@Table struct Tag: Equatable, Identifiable {
  @Column(primaryKey: true)
  let title: String
  var id: String { title }
}

@Table struct ReminderTag: Equatable, Identifiable {
  let id: Int
  var reminderID: Reminder.ID
  var tagID: Tag.ID
}
```

**Same schema as**:
- upstream swift-structured-queries (for SQLite query generation tests)
- sqlite-data (for SQLite execution tests)

### Benefits of Upstream Alignment

**Using Reminder schema** (like sqlite-data):
1. ✅ Matches upstream swift-structured-queries
2. ✅ Matches sqlite-data (parallel package)
3. ✅ Can port tests from both sources
4. ✅ Can uncomment existing test files
5. ✅ Familiar domain for Point-Free ecosystem developers
6. ✅ Better documentation/learning parity

### Recommendation

**Adopt Reminder schema** to align with upstream:
- Add Reminder schema to RecordsTestSupport
- Create factory method `.withReminderData()`
- Uncomment existing test files that expect Reminder
- Port test patterns from sqlite-data
- Eventually deprecate User/Post schema

**Implementation Path**: Add Reminder schema alongside User/Post, gradually migrate all tests.

**Status**: Implemented in Phase 2 (see above)

---

## 2025-10-08 Afternoon: Upstream Test Pattern Analysis

### Critical Finding: Upstream Uses Serial Execution

**swift-structured-queries SnapshotTests.swift:4**:
```swift
@MainActor @Suite(.serialized, .snapshots(record: .failed)) struct SnapshotTests {}
```

**The `.serialized` trait prevents parallel execution!**

### Why This Works for Upstream (SQLite)

1. **In-memory database** = instant setup (microseconds)
2. **`.serialized`** = no parallel execution = no conflicts
3. **Shared database** = simpler dependency injection
4. **Manual cleanup** = tests delete records at start

**sqlite-data pattern**:
```swift
@Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
  @Dependency(\.defaultDatabase) var database

  @Test func test() async throws {
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

### Why This Doesn't Work for PostgreSQL

| Aspect | SQLite (Upstream) | PostgreSQL (Us) |
|--------|-------------------|-----------------|
| Setup | `Database()` = instant | Schema creation = 100-200ms |
| Parallel | `.serialized` = serial only | **REQUIRED** for Cmd+U |
| Cleanup | Drop in-memory DB = instant | Schema cleanup = slow |
| Shared State | Acceptable with serial | **CONFLICTS** with parallel |

### PostgreSQL Requirements

**Why parallel execution is required**:
1. **User requirement**: "tests must pass with Cmd+U"
2. **Performance**: Serial would be too slow with PostgreSQL setup time
3. **Real-world**: Production code runs with concurrency
4. **CI/CD**: Parallel tests = faster pipelines

### Options Evaluated

1. **Transaction Rollback** - Database handles concurrency naturally, fast, production-like ❌ (actor bottleneck)
2. **Isolated Schemas** - Complete isolation but slow, fights PostgreSQL's concurrency ⚠️ (initially tried)
3. **Serial Execution** - Matches upstream but doesn't meet requirements ❌ (too slow)
4. **Direct Database Creation** - Each suite creates own database, no shared coordination ✅ (final solution)

### Key Insight

**Upstream pattern doesn't translate directly** because:
- SQLite serializes writes within the database (single writer)
- PostgreSQL handles concurrent writes natively (MVCC)
- SQLite in-memory setup is instant
- PostgreSQL schema creation takes ~200ms

**Our solution**: Embrace PostgreSQL's concurrency with suite-level databases created directly, bypassing shared coordination points.

---

## 2025-10-09 Afternoon: Test Database Simplification

### Objective

Complete migration to Reminder schema by removing User/Post schema entirely and simplifying TestDatabaseSetupMode from 5 modes to 1.

### Changes Made

#### 1. Deleted User/Post Schema

- **Removed**: `Sources/RecordsTestSupport/TestModels.swift`
- **Reason**: Diverged from upstream, no longer needed
- **Impact**: All tests now use upstream-aligned Reminder schema exclusively

#### 2. Refactored TestDatabaseSetupMode

**From enum (5 modes)**:
```swift
public enum TestDatabaseSetupMode {
    case empty
    case withSchema          // User/Post
    case withSampleData      // User/Post + data
    case withReminderSchema  // Reminder only
    case withReminderData    // Reminder + data
}
```

**To extensible struct (1 core mode)**:
```swift
public struct TestDatabaseSetupMode: Sendable {
    let setup: @Sendable (any Database.Writer) async throws -> Void

    public init(setup: @escaping @Sendable (any Database.Writer) async throws -> Void) {
        self.setup = setup
    }

    public static let withReminderData = TestDatabaseSetupMode { db in
        try await db.createReminderSchema()
        try await db.insertReminderSampleData()
    }
}
```

**Benefits**:
- **Extensible**: Users can define custom setup modes via public init
- **Simpler**: Only one mode needed for all current tests
- **Upstream aligned**: Matches sqlite-data patterns exactly
- **Type-safe**: Closures provide flexibility with compile-time safety

**Example of custom mode**:
```swift
// User can create custom setup mode
extension Database.TestDatabaseSetupMode {
    static let myCustomSetup = TestDatabaseSetupMode { db in
        try await db.createReminderSchema()
        // Custom setup logic here
    }
}
```

#### 3. Updated All Tests

**Changed 11 test files** to use single `.withReminderData()` setup:
- DatabaseAccessTests.swift
- TransactionTests.swift
- StatementExtensionTests.swift
- DraftInsertTests.swift
- SelectExecutionTests.swift
- InsertExecutionTests.swift
- UpdateExecutionTests.swift
- DeleteExecutionTests.swift
- IntegrationTests.swift
- BasicTests.swift
- PostgresJSONBTests.swift

**Before**:
```swift
@Suite(
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withSampleData()
    }
)
```

**After**:
```swift
@Suite(
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
```

### Results

- ✅ Single source of truth: Reminder schema only
- ✅ Extensible pattern for future custom setups
- ✅ Full upstream alignment with sqlite-data
- ✅ Simplified test infrastructure (from 5 modes to 1)
- ✅ All 94 tests passing with cmd+U
- ✅ Cleaner, more maintainable codebase

### Files Modified

**Deleted**:
- `Sources/RecordsTestSupport/TestModels.swift` (User/Post schema)

**Modified**:
- `Sources/RecordsTestSupport/TestDatabase.swift` - Refactored TestDatabaseSetupMode from enum to struct
- `Sources/RecordsTestSupport/TestDatabaseHelper.swift` - Simplified factory methods
- 11 test files - Updated to `.withReminderData()`

---

## Historical Reference: Completed Work

This section consolidates key findings from various debugging and development phases.

### SEQUENCE_FIX: PostgreSQL SERIAL Behavior

**Problem**: PostgreSQL SERIAL sequences don't auto-update with explicit ID inserts

**Root Cause**:
```sql
INSERT INTO "reminders" ("id", ...) VALUES (1, ...), (6, ...)
-- Sequence still at 1! Next auto-generated ID = 1 → CONFLICT
```

**Solution**: Call `setval(pg_get_serial_sequence('"tableName"', 'id'), MAX(id))` after inserts

**Learning**:
- Quoted table names have quoted sequence names
- Use `pg_get_serial_sequence()` to handle both cases
- Unquoted `users` → sequence `users_id_seq`
- Quoted `"reminders"` → sequence `"reminders_id_seq"` (with quotes!)

**Status**: ✅ Fixed in Phase 4

---

### DATE_TYPE_FIX: PostgreSQL DATE vs TIMESTAMP

**Problem**: DATE type stores only YYYY-MM-DD, loses time component

**Root Cause**:
```
Input:  2025-10-09 15:30:45
Stored: 2025-10-09 00:00:00 (midnight!)
```

**Solution**: Compare date components only in tests:
```swift
let calendar = Calendar.current
let insertedComponents = calendar.dateComponents([.year, .month, .day], from: futureDate)
let retrievedComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
#expect(insertedComponents == retrievedComponents)
```

**PostgreSQL date types**:
- `DATE`: Date only (YYYY-MM-DD)
- `TIMESTAMP`: Date + time
- `TIMESTAMPTZ`: Date + time + timezone

**Status**: ✅ Fixed in Phase 4

---

### TRANSACTION_ROLLBACK_REFACTOR: Removed Transaction Wrappers

**Change**: Removed all `withRollback` usage (44 instances)

**Replaced with**:
- Direct `db.read { }` and `db.write { }` calls
- Manual cleanup after mutations

**Reason**: Actor bottleneck prevented parallel execution. All tests queued behind same Database.Writer actor when calling `withRollback`.

**Status**: ✅ Completed during parallel test debugging

---

### PER_TEST_DATABASE_PATTERN: Connection Exhaustion

**Problem**: Creating database per test exhausted PostgreSQL connections

**Numbers**:
- 44 tests × 5 connections per pool = 220 connections
- PostgreSQL max connections: 100
- Result: Connection exhaustion

**Solution**: Suite-level shared database with schema isolation

**Learning**: PostgreSQL has connection limits. Schema isolation per suite is more efficient than database per test.

**Status**: ✅ Resolved by moving to suite-level databases

---

### DEDUPLICATION: Package Boundary Clarification

**Problem**: ~750 lines of duplicate query language code in swift-records

**Root Cause**: When swift-structured-queries-postgres was forked, aggregate/scalar functions were removed. swift-records filled the gap by duplicating query language code.

**Solution**:
- Deleted 6 extension files from swift-records
- Moved PostgreSQL-specific features to swift-structured-queries-postgres:
  - `ilike()` operator (PostgreSQLFunctions.swift)
  - PostgreSQL aggregates: `arrayAgg()`, `jsonAgg()`, `jsonbAgg()`, `stringAgg()`
  - Statistical functions: `stddev()`, `stddevPop()`, `stddevSamp()`, `variance()`

**Package Boundaries Clarified**:
- **swift-structured-queries-postgres**: Query building (NO execution)
- **swift-records**: Database operations (NO query building)

**Status**: ✅ Completed in Phase 3

---

### RESOURCE_POOL_INTEGRATION: Professional-Grade Pooling

**Implementation**: Integrated swift-resource-pool for test database management

**Features Added**:
- FIFO fairness with direct handoff
- Comprehensive metrics (wait times, handoff rates, utilization)
- Sophisticated pre-warming (synchronous first + background remainder)
- Resource validation and cycling

**Migration**: All factory methods became async to support ResourcePool initialization

**Files Modified**:
- Package.swift - Added swift-resource-pool dependency
- TestDatabase+PoolableResource.swift (NEW) - PoolableResource conformance
- TestDatabaseHelper.swift - ResourcePool integration
- TestMetrics.swift (NEW) - Observability infrastructure
- All 11 test files - Updated to async .dependencies pattern

**Status**: ✅ Completed 2025-10-08

---

### Phase Completions Summary

**PHASE_1_COMPLETE**: Test Cleanup
- Deleted 17 duplicate test files
- Established clear package boundaries
- Status: ✅ Completed (~1 hour)

**PHASE_2_COMPLETE**: Reminder Schema Implementation
- Created comprehensive Reminder schema
- Added 49 execution tests
- Implemented sample data
- Status: ✅ Completed (~2 hours)

**PHASE_4_COMPLETE**: PostgreSQL-Specific Fixes
- SERIAL Sequence Fix
- DATE Type Fix
- All 94 tests passing
- Status: ✅ Completed (~1 hour)

---

## Future Entries

(Append new dated sections here as significant changes occur)
