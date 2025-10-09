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
