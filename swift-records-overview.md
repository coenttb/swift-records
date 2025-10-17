# Swift-Records Package Architecture Overview

## File Structure

```
Sources/Records/
├── Core/
│   ├── Database.swift                      # Main namespace and documentation
│   ├── Database.Reader.swift               # Reader protocol (read-only access)
│   ├── Database.Writer.swift               # Writer protocol (read-write access)
│   ├── Database.Connection.swift           # Connection wrapper for PostgresConnection
│   ├── DatabaseProtocol.swift              # Connection.Protocol (internal API)
│   ├── Database.PostgresClient.swift       # PostgresClient Writer conformance
│   ├── Database.ClientRunner.swift         # ClientRunner (main implementation)
│   ├── Database.Error.swift                # Error types
│   ├── Database.Cursor.swift               # Async cursor for streaming results
│   ├── Table+Database.swift                # Table extensions
│   └── PostgresNIO/
│       ├── PostgresQueryDecoder.swift      # Row decoding
│       ├── PostgresQueryCursor.swift       # PostgresNIO cursor wrapper
│       └── QueryFragment+PostgresQuery.swift  # QueryFragment conversion
├── Transaction/
│   ├── Database.Writer+Transaction.swift   # Transaction extensions
│   ├── TransactionConnection.swift         # In-transaction wrapper
│   └── TransactionIsolationLevel.swift     # Isolation levels enum
├── Migration/
│   ├── Database.Migrator.swift             # Migration tracking and execution
│   └── Database.Migrator.Migration.swift   # Migration table access
├── Dependencies/
│   └── Database.DependencyKey.swift        # Dependency injection setup
├── Triggers/
│   └── Database.Trigger.swift              # Trigger support (delegates to swift-structured-queries)
├── Extensions/
│   └── Collation.swift                     # PostgreSQL collation support
├── FullTextSearch/
│   └── Database+FullTextSearch.swift       # Full-text search support
└── exports.swift                           # Public API exports

RecordsTestSupport/
├── exports.swift
├── TestDatabase.swift                      # Test database setup
├── TestConnection.swift                    # Test connection
├── TestDatabaseHelper.swift                # Helper utilities
├── ReminderSchema.swift                    # Example schema for tests
└── AssertQuery.swift                       # Query assertion helpers
```

## Core Type Hierarchy

```
Database (namespace enum)
├── Reader (protocol)
│   └── Implements: read(block)
│       └── close()
│
├── Writer (protocol, extends Reader)
│   └── Implements: write(block)
│
├── Connection (struct, conforming to Connection.Protocol)
│   ├── postgres: PostgresConnection (internal bridge)
│   └── logger: Logger
│
├── ClientRunner (final class, conforming to Writer)
│   ├── client: PostgresClient
│   ├── runTask: Task<Void, Never>
│   └── Manages: client lifecycle
│
├── Pool (typealias = ClientRunner)
│   └── factory: Database.pool(config, minConnections, maxConnections)
│
├── Queue (typealias = ClientRunner)
│   └── factory: Database.singleConnection(config)
│
├── TransactionConnection (struct, conforming to Connection.Protocol)
│   ├── underlying: Connection.Protocol
│   └── transactionDepth: Int
│
└── Error (enum)
    ├── poolShuttingDown
    ├── connectionTimeout(TimeInterval)
    ├── poolExhausted(maxConnections)
    ├── notConfigured
    ├── duplicateMigration(identifier)
    ├── migrationFailed(identifier, error)
    ├── schemaChangeDetected(message)
    ├── transactionFailed(error)
    └── invalidConfiguration(message)
```

## Connection Lifecycle

### Startup Flow

1. **Configuration**
   - `PostgresClient.Configuration` created with host, port, database, credentials
   - Min/max connections configured via `options.minimumConnections` and `options.maximumConnections`

2. **Client Creation**
   ```
   PostgresClient(configuration) → ClientRunner init(client)
       ↓
   Task { await client.run() } (started in background)
       ↓
   Task globally stored (prevents deallocation)
       ↓
   Sleep 10ms for initialization
   ```

3. **Connection Pool Management** (via PostgresNIO)
   - Minimum connections established during initialization
   - Additional connections created on-demand up to maximum
   - Connections idle-timed out after 60 seconds (configurable)
   - Keep-alive queries every 30 seconds (configurable)

### Read Operation Flow

```
db.read { db in ... }
   ↓
ClientRunner.read()
   ↓
PostgresClient.withConnection { postgresConnection in ... }
   ↓
Database.Connection(postgresConnection) created
   ↓
User closure executes with Connection
   ↓
Connection returns to pool
```

### Write Operation Flow

```
db.write { db in ... }
   ↓
ClientRunner.write()
   ↓
PostgresClient.withConnection { postgresConnection in ... }
   ↓
Database.Connection(postgresConnection) created
   ↓
User closure executes with Connection
   ↓
Connection returns to pool
```

### Transaction Flow

```
db.withTransaction(isolation: .readCommitted) { db in ... }
   ↓
write { db in
    ↓
    execute("BEGIN ISOLATION LEVEL READ COMMITTED")
    ↓
    Database.TransactionConnection(db, depth: 1) created
    ↓
    User closure executes with TransactionConnection
    ↓
    if success: execute("COMMIT")
    if error: execute("ROLLBACK") then throw
}
```

### Nested Transaction / Savepoint Flow

```
Inside transaction: db.withNestedTransaction { db in ... }
   ↓
if transactionDepth > 0 (already in transaction):
   withSavepoint(autogenerated_name) { db in ... }
       ↓
       execute("SAVEPOINT sp_...")
       ↓
       TransactionConnection(underlying, depth++) created
       ↓
       User closure executes
       ↓
       if success: execute("RELEASE SAVEPOINT")
       if error: execute("ROLLBACK TO SAVEPOINT")
```

### Shutdown Flow

```
db.close()
   ↓
runTask.cancel()
   ↓
PostgresNIO async cleanup triggered
   ↓
All connections gracefully closed
   ↓
client.run() task exits
```

## API Design Patterns

### 1. Protocol-Based Architecture

- **Reader** protocol for read-only operations
- **Writer** protocol extends Reader for read-write
- **Connection.Protocol** for query execution
- Enables dependency injection and testing

### 2. Closure-Based Access (Lending Pattern)

```swift
try await db.read { db in
    // db is borrowed for duration of closure
    // Connection automatically returned to pool after closure
}
```

Benefits:
- Prevents connection leaks (guaranteed cleanup)
- Clear connection lifecycle
- Fits with async/await semantics

### 3. Sendable Everywhere

All types are `Sendable`:
- Safe concurrent access
- Full strict concurrency support
- Actor-safe operations

### 4. Generic Result Types

```swift
func read<T: Sendable>(_ block: @Sendable (...) -> T) -> T
```

- Type-safe result handling
- Supports any return type
- Follows async/await patterns

### 5. SQL Fragment Abstraction

```swift
// High-level (via swift-structured-queries)
try await User.fetchAll(db)

// Mid-level (Statement interface)
try await db.fetchAll(User.all)

// Low-level (raw SQL)
try await db.execute("SELECT * FROM users")
```

### 6. Error Handling Patterns

```swift
do {
    try await db.write { db in ... }
} catch Database.Error.poolExhausted(let max) {
    // Specific error handling
} catch {
    // General error handling
}
```

### 7. Async/Await Streaming (Cursors)

```swift
let cursor = try await db.fetchCursor(User.all)
for try await user in cursor {
    await processUser(user)
}
```

- Memory-efficient for large result sets
- AsyncSequence conformance
- Connection held until iteration complete

## Key Design Decisions

### 1. No Connection Pooling Layer - Uses PostgresNIO Directly

**Why**: PostgresNIO has battle-tested, optimized connection pooling.

**Benefit**: 
- Reduced complexity (no reimplementation)
- Better resource usage
- Proven reliability

### 2. ClientRunner as the Main Implementation

**Why**: Single type wraps PostgresClient for both single and pooled connections.

**Benefit**:
- Unified API (Queue and Pool are aliases)
- Flexible min/max connections
- Easy to understand

### 3. Actor-Based Connection Management (postgres-nio internals)

**Why**: PostgresNIO handles all concurrency internally.

**Benefit**:
- Thread-safe without explicit locking
- High performance
- Async-first design

### 4. Transaction Wrapper Layer

**TransactionConnection** tracks transaction state:
- `transactionDepth` tracks nesting
- Savepoints for nested transactions
- Automatic or manual savepoint names

**Why**:
- Supports arbitrary nesting depth
- Clear transaction boundaries
- Automatic savepoint handling

### 5. Protocol-Based Query Execution

**Connection.Protocol** abstracts query execution:
- `execute(Statement<()>)` - No return
- `execute(String)` - Raw SQL
- `fetchAll(Statement<QueryValue>)` - Multiple rows
- `fetchOne(Statement<QueryValue>)` - Single row
- `fetchCursor(Statement<QueryValue>)` - Streaming

**Why**:
- Decouples Records from implementation details
- Easy to mock for testing
- Clear semantic boundaries

## Extension Points for LISTEN/NOTIFY

Based on the architecture, LISTEN/NOTIFY support should integrate at these levels:

### 1. **Connection Level** (Lowest)
```
Database.Connection.Protocol
├── Public: execute(), fetchAll(), fetchOne(), etc.
└── Private: postgres (PostgresConnection from postgres-nio)
```

**Opportunity**: Add methods to Connection.Protocol:
- `listen(channel: String)` 
- `notify(channel: String, payload: String)`
- `onNotification(channel: String) -> AsyncStream<Notification>`

**Challenge**: Notifications are connection-specific; need to handle pooled connections.

### 2. **Pool/Queue Level** (Recommended)
```
Database.Writer / Database.Reader
├── read() - Borrows connection from pool
└── write() - Borrows connection from pool
```

**Opportunity**: Add notification subscription manager:
```swift
extension Database.Writer {
    func subscribe(to channel: String) -> AsyncStream<Notification>
    func notify(on channel: String, payload: String) async throws
}
```

**Advantage**: 
- Can maintain dedicated LISTEN connections
- Separate from query connections
- Proper cleanup on close()

### 3. **Integration with ClientRunner**

```
ClientRunner (final class)
├── client: PostgresClient (manages connection pool)
├── runTask: Task<Void, Never> (manages client lifecycle)
└── [NEW] notificationManager: NotificationManager
```

**Pattern**:
- Create a separate notification actor
- Maintain dedicated connection for LISTEN
- Route notifications to subscribers
- Integrate with close() for cleanup

### 4. **Dependency Injection**

```swift
@Dependency(\.defaultDatabase) var db
@Dependency(\.notificationService) var notifications

// Subscribe to notifications
for try await notification in db.subscribe(to: "user_events") {
    await handleNotification(notification)
}
```

## Current API Surface

### Reader Protocol
- `read<T>(_ block:) -> T` - Read-only operation
- `close()` - Cleanup

### Writer Protocol (extends Reader)
- `write<T>(_ block:) -> T` - Read-write operation
- Inherits `read()` and `close()`

### Connection.Protocol
- `execute(_ statement:)` - Execute statement with no return
- `execute(_ sql:)` - Execute raw SQL
- `executeFragment(_ fragment:)` - Execute QueryFragment
- `fetchAll(_ statement:)` - Fetch all results
- `fetchOne(_ statement:)` - Fetch single result
- `fetchCursor(_ statement:)` - Stream results
- `withNestedTransaction(isolation:_:)` - Start nested transaction
- `withSavepoint(_:_:)` - Create savepoint

### Writer Extensions
- `withTransaction(isolation:_:)` - Begin transaction
- `withRollback(_:)` - Transaction with automatic rollback
- `withNestedTransaction(isolation:_:)` - Nested transaction
- `withSavepoint(_:_:)` - Create savepoint

### Factory Methods
- `Database.pool(configuration, minConnections, maxConnections)` -> ClientRunner
- `Database.singleConnection(configuration)` -> ClientRunner

## Testing Infrastructure

### Schema Isolation
- Each test suite gets isolated PostgreSQL schema
- Parallel test execution supported
- Schema automatically cleaned up after tests

### RecordsTestSupport
- `TestDatabase` - In-memory test setup
- `TestDatabaseHelper` - Utility functions
- `AssertQuery` - Query assertion helpers

### Test Pattern
```swift
@Suite("Tests", .dependency(\.database, try Database.TestDatabase()))
struct MyTests {
    @Dependency(\.database) var db
    
    @Test func myTest() async throws {
        try await db.withRollback { db in
            // Test operations
        }
    }
}
```

## Dependencies

- **postgres-nio** (v1.21.0+) - PostgreSQL driver
- **swift-structured-queries-postgres** - Query building
- **swift-dependencies** - Dependency injection
- **swift-environment-variables** - Config from env
- **swift-snapshot-testing** - Test support
- **xctest-dynamic-overlay** - Issue reporting

## Notable Constraints

1. **No LISTEN/NOTIFY yet** - No notification support in current API
2. **Connection holds no state** - Connections are stateless after operation completes
3. **Transactions are blocking** - Must acquire exclusive write connection
4. **No cursor transaction guarantee** - Cursors are best-effort
5. **No direct connection access** - Must go through closure pattern
