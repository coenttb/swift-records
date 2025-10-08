# Upstream Test Patterns Analysis

**Date**: 2025-10-08
**Packages Analyzed**: 
- `swift-structured-queries` (SQLite query generation + execution)
- `sqlite-data` (SQLite database operations)

## Key Findings

### 1. They Run Tests **SERIALLY**, Not in Parallel!

**swift-structured-queries** (`SnapshotTests.swift:4`):
```swift
@MainActor @Suite(.serialized, .snapshots(record: .failed)) struct SnapshotTests {}
```

**The `.serialized` trait prevents parallel execution!**

### 2. In-Memory SQLite Database

**swift-structured-queries** (`Schema.swift:88`):
```swift
static func `default`() throws -> Database {
    let db = try Database()  // No path = in-memory SQLite
    try db.migrate()
    try db.installTriggers()
    try db.seedDatabase()
    return db
}
```

**sqlite-data** (`IntegrationTests.swift:76-78`):
```swift
fileprivate static func syncUps() throws -> Self {
    let database = try DatabaseQueue()  // No path = in-memory SQLite
    var migrator = DatabaseMigrator()
    // ... migrations
}
```

### 3. Shared Database at Suite Level

Both packages use **suite-level shared database**:

```swift
@Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
  @Dependency(\.defaultDatabase) var database
  
  @Test func myTest() async throws {
    // Uses shared database
  }
}
```

### 4. Tests Clean Up After Themselves (Sometimes)

**sqlite-data** (`FetchAllTests.swift:14`):
```swift
@Test func concurrency() async throws {
    try await database.write { db in
        try Record.delete().execute(db)  // DELETE ALL at start!
    }
    // ... test operations
}
```

## Why This Works for Upstream

1. **SQLite in-memory** = fast setup/teardown (microseconds)
2. **`.serialized`** = no parallel execution = no conflicts
3. **Shared database** = simpler dependency injection
4. **Manual cleanup** = some tests delete all records at start

## Why This Doesn't Work for PostgreSQL

| Aspect | SQLite (Upstream) | PostgreSQL (Us) |
|--------|-------------------|-----------------|
| **Setup** | `Database()` = in-memory, instant | Schema creation = 100-200ms |
| **Parallel** | `.serialized` = serial only | **REQUIRED** for Cmd+U |
| **Cleanup** | Drop in-memory DB = instant | Schema cleanup = slow |
| **Shared State** | Acceptable with serial execution | **CONFLICTS** with parallel |

## PostgreSQL-Specific Requirements

### Why We MUST Support Parallel Execution

1. **User requirement**: "tests must pass with Cmd+U" (parallel by default)
2. **Performance**: Serial execution would be too slow with PostgreSQL setup time
3. **Real-world**: Production code runs with concurrency
4. **CI/CD**: Parallel tests = faster pipelines

### Options for PostgreSQL

#### Option 1: Transaction Rollback ✅ **RECOMMENDED**
```swift
@Test func myTest() async throws {
    try await db.withRollback { db in
        // All operations here
        // Automatic ROLLBACK at end
    }
}
```

**Benefits**:
- ✅ Database handles concurrency (as it should!)
- ✅ Fast (no schema overhead)
- ✅ Production-like
- ✅ Clean test code

**Drawbacks**:
- ⚠️ Need to wrap every test
- ⚠️ Seed data must be repeatable

#### Option 2: Isolated Schemas (Current)
```swift
@Test func myTest() async throws {
    try await Database.TestDatabase.isolated().run { db in
        // Each test gets own PostgreSQL schema
    }
}
```

**Benefits**:
- ✅ Complete isolation
- ✅ No shared state

**Drawbacks**:
- ❌ Slow (schema creation overhead)
- ❌ Fights PostgreSQL's concurrency model
- ❌ Complex cleanup
- ❌ Not how upstream works

#### Option 3: Serial Execution (Like Upstream)
```swift
@Suite(.serialized)
struct MyTests { ... }
```

**Benefits**:
- ✅ Matches upstream pattern
- ✅ Simple shared database

**Drawbacks**:
- ❌ Doesn't meet requirement ("tests must pass with Cmd+U")
- ❌ Very slow with PostgreSQL setup time
- ❌ Defeats purpose of fast tests

## Recommendation

**Use Option 1 (Transaction Rollback)** because:

1. **Meets business requirement**: Tests pass with Cmd+U (parallel)
2. **Respects PostgreSQL**: Database handles concurrency naturally
3. **Fast**: No schema creation overhead
4. **Production-like**: Matches how real apps use transactions
5. **Similar to upstream cleanup pattern**: Like their `Record.delete().execute(db)`

### Implementation

```swift
// Provide both patterns

// Pattern 1: Transaction rollback (recommended for parallel)
@Test func myTest() async throws {
    try await db.withRollback { db in
        // Test operations
    }
}

// Pattern 2: Serial with shared DB (matches upstream)
@Suite(.serialized, .dependency(\.defaultDatabase, ...))
struct MyTests {
    @Dependency(\.defaultDatabase) var db
    
    @Test func myTest() async throws {
        // Can use shared db
    }
}
```

## Conclusion

**Upstream uses serial execution with in-memory SQLite** - this is perfect for their use case.

**We need parallel execution with PostgreSQL** - this requires a different approach:
- ✅ Transaction rollback (recommended)
- ⚠️ Isolated schemas (current, but overkill)
- ❌ Serial execution (doesn't meet requirements)

The key insight: **PostgreSQL already handles concurrency perfectly**. We should leverage that with transaction rollback, not fight it with isolated schemas.
