# Database-Postgres: SharingGRDB-Style API for PostgreSQL

## Project Overview
A lightweight Swift package that provides SharingGRDB-like APIs for PostgreSQL by wrapping swift-structured-queries-postgres. This package acts as an elegant bridge between structured-queries statements and PostgreSQL execution, without reimplementing core database functionality.

## Key Design Principles
1. **Minimal Wrapper**: All database operations delegate to swift-structured-queries-postgres
2. **SharingGRDB API Compatibility**: Support the same patterns used in SharingGRDB examples (especially the Reminders app)
3. **Swift-Structured-Queries First**: Use @Table macro and type-safe queries from structured-queries
4. **Zero Reimplementation**: Core database features remain in swift-structured-queries-postgres
5. **Actor-Based Concurrency**: Use Swift 6 actors instead of locks for thread safety

## Functionality to Move from swift-structured-queries-postgres

The following components should be moved to database-postgres to keep swift-structured-queries-postgres as a pure integration library:

### 1. **DatabaseService & Configuration**
- Move `DatabaseService.swift` entirely to database-postgres
- Move `DatabaseConfiguration` struct with environment variable support
- This provides higher-level abstractions that aren't core to the PostgresNIO integration

### 2. **Connection Pooling**
- Move `ConnectionPool` actor to database-postgres
- Move `DatabaseConnectionPool` implementation
- Keep only basic single-connection support in swift-structured-queries-postgres
- Pooling is an application-level concern, not a core integration feature

### 3. **Transaction Management**
- Move `withTransaction` and `withRollback` methods to database-postgres
- Move `TransactionIsolationLevel` enum
- These provide convenience APIs on top of raw SQL execution

### 4. **Database Read/Write Pattern**
- Move the `read`/`write` pattern implementation to database-postgres
- This is a GRDB-style API pattern, not core PostgresNIO integration

### 5. **Migration System**
- Any migration-related code should live in database-postgres
- This is an application-level feature, not core integration

### 6. **Cursor Management**
- Move high-level cursor APIs to database-postgres
- Keep only basic PostgresQueryCursor in swift-structured-queries-postgres

### 7. **Error Types**
- Move application-level errors (poolShuttingDown, connectionTimeout) to database-postgres
- Keep only PostgreSQL-specific errors in swift-structured-queries-postgres

## What Remains in swift-structured-queries-postgres

After refactoring, swift-structured-queries-postgres should only contain:

1. **PostgresQueryDatabase**: Basic wrapper around PostgresConnection with execute methods
2. **PostgresStatement**: Converts QueryFragment to PostgresQuery
3. **PostgresQueryDecoder**: Decodes PostgresRow to Swift types  
4. **PostgresQueryCursor**: Basic cursor over PostgresRowSequence
5. **TransactionIsolationLevel**: PostgreSQL transaction isolation levels (already there)
6. **Direct execute methods**: Simple pass-through to PostgresNIO

Note: Some items like TransactionIsolationLevel and basic connection pooling are already in swift-structured-queries-postgres and should remain there as they're part of the core PostgreSQL integration.

## Core API Patterns (as seen in SharingGRDB Reminders app)

### 1. Database Read/Write Pattern
```swift
// Actual patterns from SharingGRDB/Reminders:
try await database.write { db in
    try Reminder.insert { Reminder.Draft(...) }.execute(db)
    try RemindersList.upsert { ... }.execute(db)
    try Reminder.where { $0.id == id }.update { $0.isCompleted = true }.execute(db)
}

try await database.read { db in
    // The key pattern: Table.all returns a SelectStatement
    let reminders = try await Reminder.all.fetchAll(db)
    let firstReminder = try await Reminder.all.fetchOne(db)
    let incomplete = try await Reminder.where { !$0.isCompleted }.fetchAll(db)
    
    // Complex queries with joins
    let withTags = try await Reminder.group(by: \.id)
        .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
        .fetchAll(db)
}
```

### 2. Statement Extensions (Key to the API)
```swift
// These extensions make the SharingGRDB patterns work:
extension Statement {
    func execute(_ db: Database) async throws where QueryValue == ()
    func fetchAll(_ db: Database) async throws -> [QueryValue.QueryOutput]
    func fetchOne(_ db: Database) async throws -> QueryValue.QueryOutput?
}

// Special handling for SelectStatement with nothing selected yet:
extension SelectStatement where QueryValue == (), Joins == () {
    func fetchCount(_ db: Database) async throws -> Int
    // Note: fetchAll/fetchOne for unselected statements require From: QueryRepresentable
    // This is why Table.all (which returns a properly selected statement) is the main pattern
}
```

### 3. Migration System
```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("Create tables") { db in
    try #sql("CREATE TABLE ...").execute(db)
}
try await migrator.migrate(database)
```

### 4. Database Configuration
```swift
// Support both DatabaseQueue (serial) and DatabasePool (concurrent)
let database = try await DatabaseQueue(configuration: config)
let database = try await DatabasePool(configuration: config)
```

## Current Implementation Status

### Completed Files

#### Package.swift
- Dependencies configured correctly
- Swift 6 language mode enabled
- All necessary packages included

#### Core/
- **Database.swift**: Protocol definitions for Database, DatabaseReader, DatabaseWriter
  - Added Sendable constraints to generic parameters to fix Swift 6 concurrency issues
  - DatabaseConnection struct bridges to PostgresQueryDatabase
- **DatabaseQueue.swift**: Actor-based serial database access (replaced NSLock with actor)
- **DatabasePool.swift**: Concurrent reads with serialized writes using WriteSerializer actor
- **Configuration.swift**: Database configuration with environment variable support

#### Extensions/
- **Statement+Postgres.swift**: Core extensions for execute/fetchAll/fetchOne
  - Special handling for SelectStatement where QueryValue == ()
  - Works with Table.all pattern from structured-queries
- **QueryCursor.swift**: Cursor implementation with actor-based iterator management
  - Temporary implementation fetches all results (not ideal for memory)

#### Transaction/
- **Transaction.swift**: Transaction support with isolation levels
  - Uses TransactionIsolationLevel from swift-structured-queries-postgres
  - Supports withTransaction, withRollback, withSavepoint

#### Migration/
- **DatabaseMigrator.swift**: Basic migration system
  - Tracks migrations in __database_migrations table
  - TODO: Implement proper row fetching for migration tracking

#### Dependencies/
- **DefaultDatabase.swift**: Integration with swift-dependencies
  - Provides defaultDatabase dependency key
  - Note: prepareDependencies already exists in swift-dependencies (no reimplementation)

### Implementation Discoveries

1. **Actor-Based Concurrency**: Replaced NSLock patterns with actors to avoid @escaping closures
2. **Sendable Constraints**: Added Sendable constraints to all generic parameters for Swift 6
3. **Table.all Pattern**: The key pattern from SharingGRDB - Tables have .all that returns a SelectStatement
4. **TransactionIsolationLevel**: Already exists in swift-structured-queries-postgres, we just reference it
5. **Configuration Reuse**: PostgresQueryDatabase.Configuration already exists, we wrap it

### Known Issues and TODOs

1. **Migration System**: 
   - Need to implement proper row fetching from __database_migrations table
   - Currently returns empty set for applied migrations

2. **Cursor Implementation**:
   - Current QueryCursor fetches all results into memory
   - Should integrate with PostgresQueryCursor from swift-structured-queries-postgres for streaming

3. **Connection Pooling**:
   - Basic pooling exists in swift-structured-queries-postgres
   - May need to move more sophisticated pooling logic to database-postgres

4. **Error Handling**:
   - Need to properly handle and wrap PostgreSQL errors
   - Add better error messages for common issues

### Architecture Decisions

1. **Why Actors Instead of Locks**: 
   - Avoids @escaping closure requirements
   - More idiomatic Swift 6 concurrency
   - Better integration with async/await

2. **Why Sendable Constraints**:
   - Required for Swift 6 strict concurrency
   - Ensures thread safety across actor boundaries
   - Prevents data races in concurrent database access

3. **Minimal Wrapper Philosophy**:
   - Database-postgres is thin layer over swift-structured-queries-postgres
   - Core PostgreSQL integration stays in swift-structured-queries-postgres
   - This package focuses on API ergonomics and patterns from SharingGRDB

## Features NOT to Implement
- GRDB's FetchableRecord/PersistableRecord (use structured-queries Table instead)
- GRDB's query builder (use structured-queries query syntax)
- SQLite-specific features
- Any database driver code (delegate to swift-structured-queries-postgres)

## Testing

### Test Environment
- **Database**: database-postgres-dev
- **User**: Admin (no password)
- **Host**: localhost
- **Port**: 5432
- **Configuration**: .env and .env.development files

### Current Test Files
- **BasicTests.swift**: Simple compilation tests
- **IntegrationTests.swift**: Demonstrates Table usage patterns (needs real database to run)

### Test Plan for database-postgres

The tests should focus on the functionality that database-postgres adds on top of swift-structured-queries-postgres, not re-test the underlying PostgreSQL integration.

#### 1. Database Access Pattern Tests (`DatabaseAccessTests.swift`)
Test the read/write pattern and actor-based concurrency:
- **testDatabaseQueueSerializesAccess**: Verify Database.Queue properly serializes all operations
- **testDatabasePoolAllowsConcurrentReads**: Verify Database.Pool allows multiple concurrent reads
- **testDatabasePoolSerializesWrites**: Verify Database.Pool serializes write operations
- **testReadWriteIsolation**: Ensure reads and writes don't interfere with each other
- **testActorConcurrency**: Test that our actor-based approach handles concurrent access correctly

#### 2. Statement Extension Tests (`StatementExtensionTests.swift`)
Test the Statement extensions that bridge to Database protocol:
- **testStatementExecute**: Verify Statement.execute(db) works correctly
- **testStatementFetchAll**: Verify Statement.fetchAll(db) returns correct results
- **testStatementFetchOne**: Verify Statement.fetchOne(db) returns single result
- **testSelectStatementFetchCount**: Verify SelectStatement.fetchCount(db) returns count
- **testTableAllPattern**: Test the Table.all.fetchAll(db) pattern from SharingGRDB

#### 3. Transaction Tests (`TransactionTests.swift`)
Test transaction management extensions:
- **testWithTransaction**: Verify transactions commit on success
- **testTransactionRollback**: Verify transactions rollback on error
- **testTransactionIsolationLevels**: Test different isolation levels work
- **testWithRollback**: Verify withRollback always rolls back
- **testWithSavepoint**: Test savepoint functionality
- **testNestedTransactions**: Test transaction nesting behavior

#### 4. Migration Tests (`MigrationTests.swift`)
Test the DatabaseMigrator functionality:
- **testMigrationTracking**: Verify migrations are tracked correctly
- **testMigrationOrdering**: Ensure migrations run in registration order
- **testMigrationIdempotency**: Verify migrations only run once
- **testMigrationRollback**: Test migration failure handling
- **testEraseDatabaseOnSchemaChange**: Test the development feature
- **testForeignKeyHandling**: Test deferred vs immediate foreign key checks

#### 5. Configuration Tests (`ConfigurationTests.swift`)
Test configuration and initialization:
- **testConfigurationFromEnvironment**: Test environment variable parsing
- **testDatabaseQueueInitialization**: Test Database.Queue creation
- **testDatabasePoolInitialization**: Test Database.Pool creation with pooling
- **testConfigurationPassthrough**: Verify config correctly passes to PostgresQueryDatabase

#### 6. Cursor Tests (`CursorTests.swift`)
Test the Database.Cursor implementation:
- **testCursorIteration**: Test iterating through results
- **testCursorNext**: Test manual next() calls
- **testCursorFetchAll**: Test fetchAll() on cursor
- **testCursorActorSafety**: Verify IteratorManager handles concurrent access
- **testEmptyCursor**: Test cursor with no results

#### 7. Dependency Integration Tests (`DependencyTests.swift`)
Test swift-dependencies integration:
- **testDefaultDatabaseDependency**: Test the dependency key works
- **testUnconfiguredDatabaseError**: Verify proper error when not configured
- **testDependencyOverride**: Test overriding database in tests
- **testWithDependencies**: Test proper scoping of database dependency

#### 8. API Compatibility Tests (`APICompatibilityTests.swift`)
Test SharingGRDB API patterns work correctly:
- **testRemindersPatterns**: Port key patterns from Reminders app
- **testTableDotAll**: Test Table.all usage
- **testWhereClause**: Test where clause patterns
- **testJoins**: Test join patterns
- **testGroupBy**: Test grouping functionality
- **testReturning**: Test RETURNING clause patterns

### Test Infrastructure Requirements

1. **Mock Database Setup**: Create a test helper that sets up an in-memory or test PostgreSQL database
2. **Test Tables**: Define @Table structs for testing (User, Post, Comment, etc.)
3. **Assertion Helpers**: Create helpers for common assertions
4. **Async Test Support**: Ensure all tests properly handle async/await
5. **Database Cleanup**: Ensure each test has a clean database state

### Testing Approach

- Tests should be isolated and not depend on each other
- Use `#expect` from Swift Testing framework
- Mock PostgresQueryDatabase where possible to avoid actual DB connections
- For integration tests, use a real PostgreSQL instance (can be Docker-based)
- Focus on the value database-postgres adds, not re-testing structured-queries

### What NOT to Test

- PostgreSQL connection handling (tested in swift-structured-queries-postgres)
- SQL generation (tested in swift-structured-queries)
- Query building syntax (tested in swift-structured-queries)
- PostgresNIO functionality (tested in postgres-nio)
- Basic type encoding/decoding (tested in swift-structured-queries-postgres)

## Example Usage (from Reminders app)
```swift
// Define models with @Table macro
@Table
struct Reminder {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

// Database operations
let database = try await Database.Pool(configuration: .fromEnvironment())

// Write operations
try await database.write { db in
    try Reminder.insert { 
        Reminder.Draft(title: "Buy milk", isCompleted: false) 
    }.execute(db)
}

// Read operations
let reminders = try await database.read { db in
    try Reminder
        .where { !$0.isCompleted }
        .order(by: \.title)
        .fetchAll(db)
}

// Migrations
var migrator = Database.Migrator()
migrator.registerMigration("Create reminders") { db in
    try #sql("""
        CREATE TABLE reminders (
            id UUID PRIMARY KEY,
            title TEXT NOT NULL,
            isCompleted BOOLEAN DEFAULT FALSE
        )
    """).execute(db)
}
try await migrator.migrate(database)
```

## Benefits
1. **Familiar API**: Developers using SharingGRDB can easily switch to PostgreSQL
2. **Clean Separation**: swift-structured-queries-postgres remains a pure integration library
3. **Type Safety**: Leverages structured-queries compile-time guarantees
4. **PostgreSQL Native**: Built specifically for PostgreSQL features
5. **Modern Swift**: Full Swift 6 concurrency with actors instead of locks
6. **Minimal Dependencies**: Only depends on what's necessary

## Namespace Update Plan

### Overview
Refactor all types to use nested namespacing under primary types to avoid polluting the global namespace. Use extensions for each nested type for better maintainability.

### Proposed Namespace Structure

#### 1. **Database Namespace**
Move all database-related types under `Database`:
```swift
// Current → Proposed
DatabaseReader → Database.Reader
DatabaseWriter → Database.Writer  
DatabaseConnection → Database.Connection (currently internal)
DatabaseQueue → Database.Queue
DatabasePool → Database.Pool
```

#### 2. **Configuration Namespace**
Configuration should also be nested:
```swift
// Current → Proposed
Configuration → Database.Configuration
ConnectionStrategy → Database.Configuration.ConnectionStrategy
```

#### 3. **Migration Namespace**
Migration-related types under a Migration namespace:
```swift
// Current → Proposed
DatabaseMigrator → Database.Migrator
ForeignKeyChecks → Database.Migrator.ForeignKeyChecks
```

#### 4. **Cursor Namespace**
```swift
// Current → Proposed
QueryCursor → Database.Cursor<Element>
IteratorManager → Database.Cursor.IteratorManager (private)
```

#### 5. **Dependency Namespace**
```swift
// Current → Proposed
DefaultDatabaseKey → Database.DependencyKey
UnconfiguredDatabase → Database.Unconfigured (private)
```

### Implementation Using Extensions

Each file will use extensions to add nested types, keeping code organized and maintainable:

#### Core/Database.swift
```swift
// Main namespace enum
public enum Database {
    // Namespace holder - never instantiated
}

// Each protocol/type in its own extension
extension Database {
    public protocol Reader: Sendable { ... }
}

extension Database {
    public protocol Writer: Reader, Sendable { ... }
}

extension Database {
    struct Connection: Database { ... } // internal
}
```

#### Core/DatabaseQueue.swift
```swift
extension Database {
    public actor Queue: Writer { ... }
}
```

#### Core/DatabasePool.swift
```swift
extension Database {
    public final class Pool: Writer { ... }
}

// Private nested type in separate extension
extension Database.Pool {
    private actor WriteSerializer { ... }
}
```

#### Core/Configuration.swift
```swift
extension Database {
    public struct Configuration: Sendable { ... }
}

extension Database.Configuration {
    public enum ConnectionStrategy: Sendable { ... }
}
```

#### Migration/DatabaseMigrator.swift
```swift
extension Database {
    public struct Migrator: Sendable { ... }
}

extension Database.Migrator {
    public enum ForeignKeyChecks: Sendable { ... }
}
```

#### Extensions/QueryCursor.swift
```swift
extension Database {
    public struct Cursor<Element: Sendable>: AsyncSequence, Sendable { ... }
}

// Private nested type in separate extension
extension Database.Cursor {
    private actor IteratorManager { ... }
}
```

#### Dependencies/DefaultDatabase.swift
```swift
extension Database {
    struct DependencyKey: Dependencies.DependencyKey { ... }
}

extension Database {
    private struct Unconfigured: Writer { ... }
}
```

### Implementation Steps

1. **Phase 1: Create Database Namespace**
   - Create `Database` enum as namespace holder in Database.swift
   - Move protocols to extensions: `Database.Reader`, `Database.Writer`
   - Move internal `DatabaseConnection` → `Database.Connection`
   - Update all protocol conformances

2. **Phase 2: Refactor Queue and Pool**
   - Move `DatabaseQueue` → `Database.Queue` in extension
   - Move `DatabasePool` → `Database.Pool` in extension
   - Move `WriteSerializer` to extension of `Database.Pool`
   - Update all instantiations and type references

3. **Phase 3: Refactor Configuration**
   - Move `Configuration` → `Database.Configuration` in extension
   - Move `ConnectionStrategy` to extension of `Database.Configuration`
   - Update all configuration usage

4. **Phase 4: Refactor Migrator**
   - Move `DatabaseMigrator` → `Database.Migrator` in extension
   - Move `ForeignKeyChecks` to extension of `Database.Migrator`
   - Update migration code

5. **Phase 5: Refactor Cursor**
   - Move `QueryCursor` → `Database.Cursor` in extension
   - Move `IteratorManager` to extension of `Database.Cursor`
   - Update cursor-related code

6. **Phase 6: Refactor Dependencies**
   - Move `DefaultDatabaseKey` → `Database.DependencyKey` in extension
   - Move `UnconfiguredDatabase` → `Database.Unconfigured` in extension
   - Update dependency registration

7. **Phase 7: Update Tests and Documentation**
   - Update all test files to use new namespaced types
   - Update CLAUDE.md with new type names
   - Update example code

### API Usage After Refactoring

```swift
// Initialization
let db = try await Database.Queue()
let pool = try await Database.Pool()
var migrator = Database.Migrator()

// Configuration
let config = Database.Configuration(
    host: "localhost",
    connectionStrategy: .pool(min: 2, max: 10)
)

// Type signatures
func process(with database: any Database.Writer) async throws { ... }
func read(from database: any Database.Reader) async throws { ... }

// Dependencies
@Dependency(\.defaultDatabase) var database: any Database.Writer
```

### Benefits of This Approach

1. **Cleaner Global Namespace**: Only `Database` is exposed globally
2. **Better Discoverability**: All database types under `Database.`
3. **Clearer Relationships**: Nested types show logical grouping
4. **Maintainable Code**: Extensions keep each type separate
5. **Swift Best Practices**: Follows API design guidelines
6. **Better Compilation**: Incremental compilation works better with extensions

## Next Steps

### Immediate Priorities
1. ~~Execute namespace update plan~~ ✅ Completed
2. Fix migration system to properly track applied migrations
3. Improve cursor implementation for memory efficiency
4. Add comprehensive tests with real PostgreSQL database (database-postgres-dev)
5. Document migration path from SharingGRDB

### Future Enhancements
1. Add database observation/notification support
2. Implement batch insert/update operations
3. Add support for PostgreSQL-specific features (arrays, JSONB, etc.)
4. Performance optimizations for large result sets
5. Better integration with PostgresQueryCursor for streaming results

## Code Quality Cleanup Plan

### 1. **Remove Dead Code**
- **TestHelper.swift**: This entire file contains unused singleton-based test infrastructure that we've replaced with dependency injection. Should be deleted.
- **StatementExtensionTestsNew.swift**: Should be renamed to just StatementExtensionTests.swift (remove the "New" suffix)
- **StatementExtensionTests.swift**: The "Old" version should be deleted or merged if there are unique tests

### 2. **Fix TODOs**
- **Database.Migrator.swift line 140**: Implement proper query to fetch migration identifiers
  - Currently returns empty array, needs to query __database_migrations table
  - This breaks migration tracking functionality

### 3. **Remove Debug Print Statements**
- **TestDatabase.swift lines 53, 65**: Remove warning print statements or convert to proper logging
- **ConfigurationTests.swift line 41**: Remove debug print statement

### 4. **Reduce @unchecked Sendable Usage**
- **TestDatabase.swift**: Consider if @unchecked Sendable is necessary
- **LazyTestDatabase**: Review if @unchecked Sendable can be avoided
- **TestDatabaseStorage**: This class should be deleted entirely

### 5. **Improve Code Organization**
- Consolidate test helpers: Merge TestDatabaseHelper.swift functionality into TestDatabase.swift
- Remove duplicate test schema creation code (exists in both TestDatabasePool and TestDatabaseHelper)

### 6. **Documentation & Comments**
- Add proper documentation comments to public APIs
- Remove excessive MARK comments (keep only major section dividers)
- Add README.md with usage examples

### 7. **Namespace Cleanup**
- Consider moving test-specific code to a separate module (DatabasePostgresTestSupport)
- This would prevent test utilities from being included in production builds

### 8. **Dependency Cleanup**
- Review if all dependencies are still needed (e.g., ConcurrencyExtras with NSLock usage)
- Update package versions to latest stable releases

### 9. **Test Suite Organization**
- Merge StatementExtensionTests and StatementExtensionTestsNew into one file
- Remove duplicate test coverage
- Ensure test names are descriptive

### 10. **Error Handling**
- Replace generic error ignoring with proper error logging
- Add specific error types for database operations

### Implementation Order:
1. Delete unused files (TestHelper.swift, duplicate test files)
2. Fix the TODO in Database.Migrator.swift
3. Remove print statements
4. Consolidate test helpers
5. Review and reduce @unchecked Sendable usage
6. Add documentation
7. Consider module reorganization for test support

This cleanup will:
- Reduce codebase complexity
- Fix broken migration tracking
- Improve maintainability
- Ensure production code doesn't include test utilities
- Make the API clearer for users