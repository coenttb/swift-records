# Upstream Analysis: sqlite-data vs swift-records

**Date**: 2025-10-08
**Purpose**: Analyze sqlite-data (SQLite database operations) as the true comparison for swift-records (PostgreSQL database operations)

---

## Executive Summary

**Key Finding**: swift-records should mirror sqlite-data's approach, NOT invent a new User/Post schema.

### The Real Package Hierarchy

```
swift-structured-queries (query language)
├── SQLite variant → _StructuredQueriesSQLite
│   └── Used by: sqlite-data
└── PostgreSQL variant → StructuredQueriesPostgres
    └── Used by: swift-records
```

### Direct Comparison

| Aspect | sqlite-data (SQLite) | swift-records (PostgreSQL) | Alignment |
|--------|---------------------|---------------------------|-----------|
| **Purpose** | Database operations | Database operations | ✅ Same |
| **Query Language** | swift-structured-queries (SQLite) | swift-structured-queries-postgres | ✅ Same pattern |
| **Test Schema** | Reminder, RemindersList | ⚠️ User, Post (WRONG) | ❌ Diverged |
| **assertQuery()** | ✅ Execution + snapshot testing | ❌ Commented out | ❌ Missing |
| **Dependency Injection** | ✅ `.dependency(\.defaultDatabase, ...)` | ✅ Has it | ✅ Aligned |
| **Test Database** | Throwaway SQLite (`:memory:`) | PostgreSQL schemas | ⚠️ Adapted (unavoidable) |

---

## sqlite-data Analysis

### Package Structure

**Package.swift**:
```swift
products: [
    .library(name: "SQLiteData", targets: ["SQLiteData"]),
    .library(name: "SQLiteDataTestSupport", targets: ["SQLiteDataTestSupport"])
]

dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),  // SQLite driver
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", ...),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", ...),
]
```

**Parallel in swift-records**:
```swift
products: [
    .library(name: "Records", targets: ["Records"]),
    .library(name: "RecordsTestSupport", targets: ["RecordsTestSupport"])
]

dependencies: [
    .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),  // PostgreSQL driver
    .package(url: "https://github.com/coenttb/swift-structured-queries-postgres", ...),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", ...),
]
```

✅ **Structure mirrors perfectly**

---

### Test Schema (The Critical Finding)

**sqlite-data uses Reminder schema** (from Tests/SQLiteDataTests/Internal/Schema.swift):

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

// ... more models
```

**Same schema as**:
- upstream swift-structured-queries (for SQLite query generation tests)
- sqlite-data (for SQLite execution tests)

**swift-records currently uses**: User, Post, Comment, Tag
- ❌ Invented schema, not aligned with upstream
- ❌ Makes porting tests from upstream harder
- ❌ Diverges from sqlite-data without justification

---

### Test Infrastructure

**sqlite-data's assertQuery()** (Sources/SQLiteDataTestSupport/AssertQuery.swift):

```swift
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
  includeSQL: Bool = false,
  _ query: S,
  database: (any DatabaseWriter)? = nil,
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  ...
) {
  if includeSQL {
    // Snapshot SQL
    assertInlineSnapshot(of: query, as: .sql, ...)
  }

  // Execute query
  @Dependency(\.defaultDatabase) var defaultDatabase
  let rows = try (database ?? defaultDatabase).write { try query.fetchAll($0) }

  // Snapshot results
  var table = ""
  printTable(rows, to: &table)
  assertInlineSnapshot(of: table, as: .lines, ...)
}
```

**Key Features**:
1. ✅ Executes query against actual database
2. ✅ Snapshots formatted results (table with borders)
3. ✅ Optional SQL snapshot (includeSQL parameter)
4. ✅ Uses dependency injection for database
5. ✅ Formats results with customDump

**Usage Example** (Tests/SQLiteDataTests/AssertQueryTests.swift):

```swift
@Suite(.dependency(\.defaultDatabase, try .database()))
struct AssertQueryTests {
  @Test func assertQueryBasic() throws {
    assertQuery(Record.all.select(\.id)) {
      """
      ┌───┐
      │ 1 │
      │ 2 │
      │ 3 │
      └───┘
      """
    }
  }

  @Test func assertQueryUpdate() throws {
    assertQuery(
      Record.all
        .update { $0.date = Date(timeIntervalSince1970: 45) }
        .returning { ($0.id, $0.date) }
    ) {
      """
      ┌───┬────────────────────────────────┐
      │ 1 │ Date(1970-01-01T00:00:45.000Z) │
      │ 2 │ Date(1970-01-01T00:00:45.000Z) │
      │ 3 │ Date(1970-01-01T00:00:45.000Z) │
      └───┴────────────────────────────────┘
      """
    }
  }
}
```

**swift-records status**:
- ✅ Has assertQuery() in RecordsTestSupport (but commented out)
- ❌ Not being used in tests
- ⚠️ Needs updating for PostgreSQL

---

### Test Database Creation

**sqlite-data approach** (per-test throwaway databases):

```swift
// Tests/SQLiteDataTests/FetchAllTests.swift
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()  // In-memory SQLite
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "date" INTEGER NOT NULL DEFAULT 42,
          "optionalDate" INTEGER
        )
        """
      ).execute(db)

      // Insert test data
      for _ in 1...3 {
        _ = try Record.insert { Record.Draft() }.execute(db)
      }
    }
    return database
  }
}

// Usage in tests
@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchAllTests {
  @Dependency(\.defaultDatabase) var database
  // Tests use 'database' for execution
}
```

**Pattern**:
1. Extension on `DatabaseWriter` (generic over database type)
2. Creates throwaway database per test suite
3. Inline schema + data creation
4. Dependency injection via `.dependency(\.defaultDatabase, ...)`

**swift-records adaptation** (PostgreSQL doesn't have in-memory):

```swift
// RecordsTestSupport/TestDatabaseHelper.swift
extension Database.TestDatabase {
    static func withSchema() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSchema)
    }

    static func withSampleData() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSampleData)
    }
}

// Usage (current pattern)
@Suite(
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withSchema())
)
struct TransactionTests {
    @Dependency(\.defaultDatabase) var database
}
```

**Key Difference**:
- SQLite: Throwaway in-memory databases
- PostgreSQL: Schema isolation via UUID-based schemas

✅ **Pattern adapted appropriately for PostgreSQL constraints**

---

### Test File Organization

**sqlite-data Tests/** (40 test files):

```
Tests/SQLiteDataTests/
├── FetchAllTests.swift          # @FetchAll property wrapper
├── FetchOneTests.swift          # @FetchOne property wrapper
├── FetchTests.swift             # @Fetch property wrapper
├── AssertQueryTests.swift       # assertQuery() testing
├── IntegrationTests.swift       # End-to-end scenarios
├── MigrationTests.swift         # Database migrations
├── QueryCursorTests.swift       # Cursor-based iteration
├── CustomFunctionTests.swift    # Custom SQL functions
├── CloudKitTests/               # CloudKit sync (26 files)
│   ├── SyncEngineTests.swift
│   ├── MergeConflictTests.swift
│   └── ...
└── Internal/
    ├── Schema.swift             # Reminder/RemindersList models
    ├── UserDatabaseHelpers.swift
    └── ...
```

**swift-records Tests/** (15 files, 27 commented out):

```
Tests/RecordsTests/
├── BasicTests.swift ✅
├── IntegrationTests.swift ✅
├── TransactionTests.swift ✅
├── DatabaseAccessTests.swift ✅
├── DraftInsertTests.swift ✅
├── Postgres/
│   ├── ExecutionUpdateTests.swift (commented - schema mismatch)
│   ├── ExecutionValuesTests.swift (commented - old API)
│   ├── LiveTests.swift (commented - schema mismatch)
│   ├── LiveTests 2.swift (commented - schema mismatch)
│   └── QueryDecoderTests.swift ✅
└── Support/
    ├── Schema.swift             # User/Post models (WRONG)
    └── support.swift
```

**Missing** (compared to sqlite-data):
- FetchAllTests.swift
- FetchOneTests.swift
- MigrationTests.swift
- Comprehensive execution tests
- assertQuery()-based tests

---

## Comparison Matrix

| Feature | sqlite-data | swift-records | Action Needed |
|---------|------------|---------------|---------------|
| **Schema** | ✅ Reminder (upstream) | ❌ User/Post (invented) | Replace with Reminder |
| **assertQuery()** | ✅ Active | ❌ Commented out | Activate & adapt |
| **Test Database** | ✅ In-memory SQLite | ✅ PostgreSQL schemas | Keep (unavoidable) |
| **FetchAll tests** | ✅ Comprehensive | ❌ Missing | Add |
| **FetchOne tests** | ✅ Comprehensive | ❌ Missing | Add |
| **Integration tests** | ✅ Many scenarios | ⚠️ Minimal | Expand |
| **Migration tests** | ✅ Has tests | ⚠️ Basic | Expand |
| **Execution tests** | ✅ Comprehensive | ❌ Mostly commented | Uncomment/adapt |

---

## Why This Matters

### Problem with Current Approach

**swift-records invented a User/Post schema**:
```swift
@Table struct User { ... }
@Table struct Post { ... }
@Table struct Comment { ... }
```

**Issues**:
1. ❌ Diverges from upstream (Reminder schema)
2. ❌ Makes porting upstream tests harder
3. ❌ Breaks commented test files (expect Reminder, not User)
4. ❌ No justification for divergence
5. ❌ sqlite-data uses Reminder, we should too

### Upstream Alignment Benefits

**Using Reminder schema** (like sqlite-data):
1. ✅ Matches upstream swift-structured-queries
2. ✅ Matches sqlite-data (parallel package)
3. ✅ Can port tests from both sources
4. ✅ Can uncomment existing test files
5. ✅ Familiar domain for Point-Free ecosystem developers
6. ✅ Better documentation/learning parity

---

## Revised Recommendation

### ❌ REJECT: Option 2 (User/Post Schema)

Original recommendation to create User/Post tests was **wrong**. This diverges from:
- upstream swift-structured-queries
- sqlite-data (the true comparison)
- Existing commented test files

### ✅ ACCEPT: Option 1 (Reminder Schema)

**Action Plan**:

1. **Keep current User/Post schema** for now (it works for active tests)

2. **Add Reminder schema** to RecordsTestSupport:
   ```swift
   // RecordsTestSupport/ReminderSchema.swift
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

   // ... Tag, ReminderTag, etc.
   ```

3. **Add schema creation helper**:
   ```swift
   extension Database.Writer {
       func createReminderSchema() async throws {
           // CREATE TABLE "remindersLists" ...
           // CREATE TABLE "reminders" ...
           // CREATE TABLE "tags" ...
           // CREATE TABLE "reminderTags" ...
       }

       func insertReminderSampleData() async throws {
           // INSERT INTO remindersLists ...
           // INSERT INTO reminders ...
       }
   }
   ```

4. **Add setup mode**:
   ```swift
   enum TestDatabaseSetupMode {
       case empty
       case withSchema              // User/Post (current)
       case withSampleData          // User/Post with data
       case withReminderSchema      // NEW: Reminder schema
       case withReminderData        // NEW: Reminder with data
   }
   ```

5. **Uncomment & fix test files**:
   - ExecutionUpdateTests.swift → use .withReminderData()
   - LiveTests.swift → merge + use .withReminderData()
   - Update API from old TestDatabase.create() to dependency injection

6. **Activate assertQuery()**:
   - Uncomment RecordsTestSupport/AssertQuery.swift
   - Adapt for PostgreSQL (fetchAll instead of execute)
   - Add tests using assertQuery()

7. **Port tests from sqlite-data**:
   - FetchAllTests.swift pattern
   - FetchOneTests.swift pattern
   - Use Reminder schema for alignment

---

## Code Examples

### sqlite-data Pattern (to copy)

```swift
// Test with inline database creation
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func reminders() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      // Create schema
      try RemindersList.createTable().execute(db)
      try Reminder.createTable().execute(db)

      // Insert data
      try RemindersList.insert {
        RemindersList.Draft(id: 1, title: "Home")
      }.execute(db)

      try Reminder.insert {
        Reminder.Draft(id: 1, title: "Buy groceries", remindersListID: 1)
      }.execute(db)
    }
    return database
  }
}

@Suite(.dependency(\.defaultDatabase, try .reminders()))
struct ReminderTests {
  @Test func selectReminders() throws {
    assertQuery(Reminder.all) {
      """
      ┌─────────────────────────────────────┐
      │ Reminder(                           │
      │   id: 1,                            │
      │   title: "Buy groceries",           │
      │   remindersListID: 1                │
      │ )                                   │
      └─────────────────────────────────────┘
      """
    }
  }
}
```

### swift-records Adaptation

```swift
// RecordsTestSupport/ReminderDatabase.swift
extension Database.TestDatabase {
    static func withReminders() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withReminderData)
    }
}

// Test usage
@Suite(
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminders())
)
struct ReminderExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func selectReminders() async throws {
        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }

        #expect(reminders.count > 0)
        #expect(reminders[0].title == "Buy groceries")
    }

    // Or with assertQuery (once activated)
    @Test func selectRemindersSnapshot() throws {
        assertQuery(Reminder.all) {
            """
            ┌─────────────────────────────────────┐
            │ Reminder(                           │
            │   id: 1,                            │
            │   title: "Buy groceries",           │
            │   remindersListID: 1                │
            │ )                                   │
            └─────────────────────────────────────┘
            """
        }
    }
}
```

---

## Implementation Effort

**Revised Phase 2 Estimate**: 3-4 hours (vs. 4-6 for User/Post rewrite)

### Tasks

1. **Add Reminder schema** (1 hour)
   - Create RecordsTestSupport/ReminderSchema.swift
   - Define @Table models matching upstream
   - Create schema helper functions

2. **Update test infrastructure** (1 hour)
   - Add .withReminderSchema / .withReminderData setup modes
   - Implement createReminderSchema()
   - Implement insertReminderSampleData()

3. **Uncomment & fix tests** (1 hour)
   - ExecutionUpdateTests.swift
   - ExecutionValuesTests.swift
   - Merge LiveTests.swift files
   - Update from old API to dependency injection

4. **Activate assertQuery()** (30 minutes)
   - Uncomment RecordsTestSupport/AssertQuery.swift
   - Adapt for PostgreSQL
   - Add test to verify it works

---

## Success Criteria

✅ **Upstream Alignment**:
- swift-records uses Reminder schema (like sqlite-data)
- Can port tests from sqlite-data easily
- assertQuery() works for execution testing

✅ **Test Coverage**:
- All 4 commented test files active and passing
- assertQuery() used for snapshot testing
- Matches sqlite-data test patterns

✅ **Maintainability**:
- Clear separation: User/Post for swift-records-specific tests, Reminder for upstream-aligned tests
- Can track upstream changes more easily
- Documentation explains both schemas

---

## Conclusion

**The User/Post schema was a well-intentioned but incorrect divergence.**

**Correct approach**:
1. Add Reminder schema (matches sqlite-data)
2. Uncomment existing test files (they expect Reminder)
3. Port test patterns from sqlite-data
4. Keep User/Post for swift-records-specific tests if needed

**This is the upstream-aligned path.**
