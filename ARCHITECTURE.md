# Architecture

**Package**: swift-records
**Last Updated**: 2025-10-09
**Purpose**: PostgreSQL database operations layer

This is a living reference document. Update this file when architecture changes.

---

## Package Overview

### Purpose
PostgreSQL database operations layer that executes type-safe queries built by swift-structured-queries-postgres. Provides connection management, pooling, transactions, and migrations.

**Core Responsibility**: Database execution (NO query building)

### Built On
- **swift-structured-queries-postgres**: Query language layer (SQL generation)
- **PostgresNIO**: Low-level PostgreSQL client
- **PostgresKit**: Additional PostgreSQL utilities
- **swift-dependencies**: Dependency injection
- **swift-resource-pool**: Connection pooling

### Package Boundaries

**This Package (swift-records)**:
- ✅ Query execution (`.execute()`, `.fetchAll()`, `.fetchOne()`)
- ✅ Connection pooling (Database.Pool)
- ✅ Transaction management
- ✅ Migration system
- ✅ Test support (schema isolation)
- ❌ NO query language code

**swift-structured-queries-postgres Package**:
- ✅ Query building (SELECT, INSERT, UPDATE, DELETE)
- ✅ Returns `Statement<QueryValue>` types
- ❌ NO database execution

**Clear Separation**:
```swift
// Query building (swift-structured-queries-postgres)
let statement = User.where { $0.isActive }

// Execution (this package)
let users = try await statement.fetchAll(db)
```

---

## Database Layer Architecture

### Connection Management

#### Database.Writer Protocol
Read/write database access with full transaction support.

**Capabilities**:
- Execute queries
- Start transactions
- Manage migrations
- Write operations

**Implementation**: Actor-based for thread safety

**Example**:
```swift
let writer: Database.Writer = Database.singleConnection(...)
try await writer.write { db in
    try await User.insert { ... }.execute(db)
}
```

#### Database.Reader Protocol
Read-only database access for queries.

**Capabilities**:
- Execute SELECT queries
- Read operations only
- No mutations allowed

**Example**:
```swift
let reader: Database.Reader = Database.singleConnection(...)
try await reader.read { db in
    try await User.all.fetchAll(db)
}
```

#### PostgresClient.Configuration

Configuration loaded from environment variables:

**Environment Variables**:
```
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=mydb
DATABASE_USER=postgres
DATABASE_PASSWORD=secret
DATABASE_SSL=false
DATABASE_POOL_SIZE=5
```

**Factory Method**:
```swift
let config = try PostgresClient.Configuration.from(
    envVars: .current
)
```

### Connection Pooling

#### ResourcePool Integration

Uses `swift-resource-pool` for professional-grade connection pooling:

**Features**:
- FIFO fairness with direct handoff (eliminates thundering herd)
- Comprehensive metrics (wait times, handoff rates, utilization)
- Sophisticated pre-warming (synchronous first + background remainder)
- Resource validation and cycling capabilities
- Graceful shutdown with timeout

**Configuration**:
```swift
ResourcePoolConfiguration(
    minimumResourceCount: 2,
    maximumResourceCount: 5,
    maximumWaitTime: .seconds(30),
    resourceLifetime: .minutes(30),
    resourceIdleTimeout: .minutes(5)
)
```

#### PoolableResource Conformance

```swift
extension Database.TestDatabase: PoolableResource {
    func isStillValid() async -> Bool {
        // Check connection is alive
    }

    func shutdown() async {
        // Clean up database resources
    }
}
```

**Lifecycle**:
1. **Creation**: Async factory method creates database
2. **Validation**: `isStillValid()` checks health
3. **Recycling**: Used resources returned to pool
4. **Shutdown**: Cleanup when removed from pool

#### Metrics and Observability

**Available Metrics**:
- Resource requests (total, direct hits, pool retrievals, creations)
- Wait times (current, total, average)
- Pool state (available, checked out, total)
- Handoff statistics (direct handoffs, requests with waits)

**Access**:
```swift
let stats = pool.statistics
print("Available: \(stats.availableResourceCount)")
print("In Use: \(stats.checkedOutResourceCount)")
```

### Reader/Writer Pattern

#### Why This Pattern?

**Benefits**:
- **Clear Intent**: Code explicitly declares read vs write
- **Type Safety**: Compiler enforces correct database access
- **Connection Optimization**: Readers can use replicas (future)
- **Transaction Scope**: Writes automatically in transaction context

#### Usage Patterns

**Read Operations**:
```swift
try await db.read { db in
    try await User.all.fetchAll(db)
}
```

**Write Operations**:
```swift
try await db.write { db in
    try await User.insert { User(name: "Alice") }.execute(db)
}
```

**Mixed Operations**:
```swift
// Read
let users = try await db.read { db in
    try await User.all.fetchAll(db)
}

// Then write
try await db.write { db in
    for user in users {
        try await User.find(user.id).update { $0.lastSeen = Date() }.execute(db)
    }
}
```

#### Actor-Based Implementation

**Database.Writer Actor**:
```swift
public actor DatabaseWriter: Database.Writer {
    private let pool: ResourcePool<PostgresConnection>

    public func write<T>(_ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T {
        // Acquire connection from pool
        // Execute operation
        // Return connection to pool
    }
}
```

**Why Actor**:
- Thread-safe access to connection pool
- Serialized write operations prevent race conditions
- Async/await friendly

### Transaction Management

#### withTransaction(isolation:)

Explicit transaction control with isolation levels:

```swift
try await db.withTransaction(isolation: .repeatableRead) { db in
    let user = try await User.find(1).fetchOne(db)
    try await User.find(1).update { $0.balance -= 100 }.execute(db)
    try await Transaction.insert { ... }.execute(db)
    // Automatic COMMIT on success, ROLLBACK on error
}
```

**Isolation Levels**:
- `.readCommitted` - Default, prevents dirty reads
- `.repeatableRead` - Prevents non-repeatable reads
- `.serializable` - Strictest, prevents phantom reads

#### withSavepoint(name:)

Nested transaction support:

```swift
try await db.withTransaction { db in
    try await User.insert { ... }.execute(db)

    try await db.withSavepoint("sp1") { db in
        try await Post.insert { ... }.execute(db)
        // ROLLBACK TO SAVEPOINT sp1 on error
    }

    // User insert still committed even if Post insert fails
}
```

#### withRollback()

Test isolation via automatic rollback:

```swift
try await db.withRollback { db in
    try await User.insert { ... }.execute(db)
    // Automatically rolled back at end
    // Useful for testing without data pollution
}
```

**Use Cases**:
- Test isolation
- Dry-run operations
- Preview changes

### Migration System

#### Version Tracking

Migrations stored in `__migrations` table:

```swift
CREATE TABLE __migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

#### Forward-Only Migrations

```swift
public struct Migration {
    public let version: Int
    public let name: String
    public let up: (Database.Writer) async throws -> Void
}
```

**Example**:
```swift
Migration(version: 1, name: "create_users") { db in
    try await db.execute("""
        CREATE TABLE users (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL
        )
    """)
}
```

#### Automatic Migration Detection

```swift
try await db.migrate(migrations: [
    createUsersTable,
    addIndexes,
    addTriggers
])
// Only runs unapplied migrations
```

**Process**:
1. Check `__migrations` table for applied versions
2. Filter out already-applied migrations
3. Run pending migrations in order
4. Record successful applications

---

## Integration with swift-structured-queries-postgres

### Package Boundary

**swift-structured-queries-postgres builds Statement**:
```swift
let statement: Statement<[User]> = User.where { $0.isActive }
```

**swift-records executes statements**:
```swift
let users = try await statement.fetchAll(db)
```

**Clear Separation**:
- Query building: Type-safe SQL generation (compile-time)
- Query execution: Runtime database operations (async)

### Execution Layer

#### Extension on Statement

```swift
extension Statement {
    public func execute(_ db: Database.Writer) async throws -> QueryValue
    public func fetchAll(_ db: Database.Reader) async throws -> [QueryValue]
    public func fetchOne(_ db: Database.Reader) async throws -> QueryValue?
}
```

#### How It Works

1. **Query Building** (swift-structured-queries-postgres):
   ```swift
   let statement = User.where { $0.id == 1 }
   // Returns Statement<[User]>
   ```

2. **SQL Generation** (swift-structured-queries-postgres):
   ```swift
   let sql = statement.sql
   // "SELECT * FROM \"users\" WHERE (\"id\" = $1)"
   ```

3. **Execution** (swift-records):
   ```swift
   let users = try await statement.fetchAll(db)
   // Executes SQL against PostgreSQL
   // Decodes rows to [User]
   ```

---

## Actor-Based Concurrency Model

### Why Actors?

**Thread Safety**:
- Actors serialize access to mutable state
- No data races with connection pools
- Safe concurrent access from multiple tasks

**PostgreSQL Benefits**:
- Each connection can only handle one operation at a time
- Actor model naturally matches this constraint
- MVCC allows concurrent transactions

**Example Race Condition (Without Actors)**:
```swift
// ❌ Unsafe without actors
class UnsafeDatabase {
    var connection: PostgresConnection

    func write<T>(_ op: (PostgresConnection) async throws -> T) async throws -> T {
        // Multiple tasks could access connection simultaneously
        return try await op(connection) // ❌ DATA RACE
    }
}
```

**Safe with Actors**:
```swift
// ✅ Safe with actor
actor DatabaseWriter {
    var connection: PostgresConnection

    func write<T>(_ op: (PostgresConnection) async throws -> T) async throws -> T {
        // Actor ensures serialized access
        return try await op(connection) // ✅ SAFE
    }
}
```

### Connection Protocol

```swift
public protocol Database.Connection.Protocol {
    func execute<QueryValue>(
        _ statement: Statement<QueryValue>
    ) async throws -> QueryValue
}
```

**Implementation**:
```swift
extension PostgresConnection: Database.Connection.Protocol {
    public func execute<QueryValue>(
        _ statement: Statement<QueryValue>
    ) async throws -> QueryValue {
        let sql = statement.sql
        let bindings = statement.bindings
        let rows = try await query(sql, bindings)
        return try QueryDecoder.decode(QueryValue.self, from: rows)
    }
}
```

---

## Public API Design

### Database Types

#### Database.Writer
Full read/write access to database.

**Methods**:
```swift
func read<T>(_ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
func write<T>(_ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
func withTransaction<T>(isolation: IsolationLevel, _ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
func withSavepoint<T>(name: String, _ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
func withRollback<T>(_ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
```

#### Database.Reader
Read-only access to database.

**Methods**:
```swift
func read<T>(_ operation: (Database.Connection.Protocol) async throws -> T) async throws -> T
```

**Why Separate Reader**:
- Enforces read-only constraint at type level
- Future: Can route to read replicas
- Clear documentation of access patterns

#### Database.Connection.Protocol
Low-level connection interface.

**Purpose**:
- Abstraction over PostgresConnection
- Allows mocking in tests
- Protocol-oriented design

### Factory Methods

#### Database.singleConnection()

Creates single-connection database:

```swift
public static func singleConnection(
    configuration: PostgresClient.Configuration? = nil
) async throws -> Database.Writer {
    let config = configuration ?? try .from(envVars: .current)
    let connection = try await PostgresClient.connect(configuration: config)
    return DatabaseWriter(connection: connection)
}
```

**Use Cases**:
- Simple applications
- Migrations
- Testing (when pool not needed)

#### Database.pool()

Creates connection-pooled database:

```swift
public static func pool(
    configuration: PostgresClient.Configuration? = nil,
    poolConfig: ResourcePoolConfiguration = .default
) async throws -> Database.Writer {
    let pool = try await ResourcePool(
        minimumResourceCount: poolConfig.minimumResourceCount,
        maximumResourceCount: poolConfig.maximumResourceCount
    ) {
        try await PostgresClient.connect(configuration: config)
    }
    return DatabaseWriter(pool: pool)
}
```

**Use Cases**:
- Production applications
- High-concurrency scenarios
- Web servers

#### Database.testDatabase()

Creates test database with schema isolation:

```swift
public static func testDatabase(
    configuration: PostgresClient.Configuration? = nil,
    prefix: String = "test"
) async throws -> Database.TestDatabase {
    let schemaName = "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
    let db = try await singleConnection(configuration: configuration)
    try await db.execute("CREATE SCHEMA \"\(schemaName)\"")
    try await db.execute("SET search_path TO \"\(schemaName)\"")
    return TestDatabase(database: db, schema: schemaName)
}
```

**Use Cases**:
- Unit tests
- Integration tests
- Parallel test execution

---

## Test Support

### TestDatabase

Schema-isolated test database with automatic cleanup:

```swift
public actor TestDatabase: Database.Writer {
    private let database: Database.Writer
    public let schema: String

    deinit {
        Task.detached { [database, schema] in
            try? await database.execute("DROP SCHEMA IF EXISTS \"\(schema)\" CASCADE")
        }
    }
}
```

**Features**:
- ✅ Isolated PostgreSQL schema per instance
- ✅ Automatic cleanup on deinit
- ✅ Full Database.Writer conformance
- ✅ Parallel test execution

### LazyTestDatabase

ResourcePool-based test database wrapper:

```swift
public final class LazyTestDatabase: Database.Writer {
    private let pool: ResourcePool<Database.TestDatabase>

    public init(
        setupMode: SetupMode,
        minimumResourceCount: Int = 2,
        maximumResourceCount: Int = 5
    ) async throws {
        self.pool = try await ResourcePool(
            minimumResourceCount: minimumResourceCount,
            maximumResourceCount: maximumResourceCount
        ) {
            try await Database.testDatabase(setupMode: setupMode)
        }
    }
}
```

**Benefits**:
- ✅ Eliminates thundering herd during parallel suite initialization
- ✅ Metrics and observability
- ✅ Resource validation
- ✅ Graceful shutdown

### Schema Setup Modes

```swift
public enum TestDatabaseSetupMode {
    case empty                     // No tables
    case withSchema                // User/Post schema
    case withSampleData            // User/Post + data
    case withReminderSchema        // Reminder schema (upstream-aligned)
    case withReminderData          // Reminder + data (most common)
}
```

**Factory Methods**:
```swift
Database.TestDatabase.withSchema()        // User/Post only
Database.TestDatabase.withSampleData()    // User/Post + data
Database.TestDatabase.withReminderSchema() // Reminder only
Database.TestDatabase.withReminderData()   // Reminder + data
```

**Usage**:
```swift
@Suite(
    "My Tests",
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct MyTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        // Database has Reminder schema + sample data
    }
}
```

---

## Performance Considerations

### Connection Pooling Strategy

**Default Configuration**:
- Minimum connections: 2
- Maximum connections: 5
- Connection lifetime: 30 minutes
- Idle timeout: 5 minutes

**Tuning Factors**:

**Too Few Connections**:
- High wait times
- Reduced throughput
- Underutilized database

**Too Many Connections**:
- PostgreSQL connection limit (default 100)
- Memory overhead per connection
- Context switching overhead

**Recommended**:
```
connections = (cores × 2) + effective_spindle_count
```

For most web apps: **2-5 connections per pool**

### Transaction Scope

**Keep Transactions Short**:
```swift
// ❌ Bad - long transaction
try await db.withTransaction { db in
    let users = try await User.all.fetchAll(db)
    for user in users {
        await processUser(user) // ❌ Slow operation in transaction
        try await User.find(user.id).update { ... }.execute(db)
    }
}

// ✅ Good - short transaction
let users = try await db.read { db in
    try await User.all.fetchAll(db)
}
for user in users {
    await processUser(user) // ✅ Outside transaction
}
try await db.write { db in
    for user in users {
        try await User.find(user.id).update { ... }.execute(db)
    }
}
```

**Use Appropriate Isolation Levels**:
- `.readCommitted` - Default, sufficient for most cases
- `.repeatableRead` - When consistent reads needed
- `.serializable` - Only when absolutely necessary (highest overhead)

### Query Optimization

**Leverage PostgreSQL Query Planner**:
```swift
// Analyze query performance
try await db.execute("EXPLAIN ANALYZE \(statement.sql)")
```

**Use Indexes Appropriately**:
```swift
// Add index for frequently-queried columns
try await db.execute("""
    CREATE INDEX idx_users_email ON users (email)
""")
```

**Avoid N+1 Queries**:
```swift
// ❌ Bad - N+1 queries
let users = try await User.all.fetchAll(db)
for user in users {
    let posts = try await Post.where { $0.userID == user.id }.fetchAll(db) // ❌
}

// ✅ Good - single join query
let usersWithPosts = try await User
    .join(Post.self) { $0.id == $1.userID }
    .fetchAll(db)
```

---

## Dependency Injection

### swift-dependencies Integration

```swift
extension Database.Writer: DependencyKey {
    public static let liveValue: Database.Writer = try! await Database.pool()
    public static let testValue: Database.Writer = try! await Database.testDatabase()
}

extension DependencyValues {
    public var defaultDatabase: Database.Writer {
        get { self[Database.Writer.self] }
        set { self[Database.Writer.self] = newValue }
    }
}
```

**Usage in Application Code**:
```swift
@Dependency(\.defaultDatabase) var db

func fetchUsers() async throws -> [User] {
    try await db.read { db in
        try await User.all.fetchAll(db)
    }
}
```

**Usage in Tests**:
```swift
@Suite(
    "User Tests",
    .dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
)
struct UserTests {
    @Dependency(\.defaultDatabase) var db

    @Test func fetchAllUsers() async throws {
        let users = try await db.read { db in
            try await User.all.fetchAll(db)
        }
        #expect(users.count == 2)
    }
}
```

---

## Architecture Health Metrics

**Current Status** (as of 2025-10-09):

- ✅ Build Status: Successful
- ✅ Test Status: 94 passing tests
- ✅ Connection Pooling: ResourcePool integrated
- ✅ Test Infrastructure: Schema isolation working
- ✅ Package Boundaries: Clean separation from query language
- ✅ Documentation: Complete

**Overall Health**: HEALTHY ✅

---

## Future Improvements

1. **Read Replicas**: Route read operations to replica databases
2. **Connection Metrics**: Enhanced observability
3. **Automatic Failover**: Handle connection failures gracefully
4. **Query Caching**: Cache frequently-executed queries
5. **Prepared Statements**: Reuse parsed queries
6. **Migration Rollback**: Support downward migrations

---

**For testing patterns and best practices, see TESTING.md**
**For historical context on architectural decisions, see HISTORY.md**
