# Swift-Records Package Architecture - Comprehensive Exploration Summary

## Overview

This exploration examined the swift-records package (v0.0.1+), a high-level PostgreSQL database abstraction library built on top of PostgresNIO and swift-structured-queries. The package is part of a larger Swift ecosystem for server-side web development centered around the Boiler framework.

## Key Findings

### 1. Architecture is Protocol-Based and Lean

**Core Abstractions**:
- `Database.Reader` - Read-only operations
- `Database.Writer` - Read-write operations (extends Reader)
- `Database.Connection.Protocol` - Low-level query execution interface
- `ClientRunner` - Manages PostgresClient lifecycle and connection pooling

**Key Design**: Only ~1,000 lines of core implementation code. The package delegates connection pooling and protocol handling to PostgresNIO, avoiding reimplementation of well-tested functionality.

### 2. Connection Lifecycle Management

**Startup**:
```
PostgresClient Configuration
    ↓
ClientRunner init + Background Task (client.run())
    ↓
Task globally stored (prevents GC deallocation)
    ↓
10ms initialization delay
    ↓
PostgresNIO manages connection pool internally
```

**Operations**: Connections are borrowed via closures, returned to pool automatically.

**Shutdown**: Clean cancellation of background task and connection cleanup.

### 3. Transaction Support is Sophisticated

- Nested transaction support via `TransactionConnection` wrapper
- Automatic savepoint generation for nesting depth > 1
- Four isolation levels: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE
- Automatic rollback on error
- Supports nested transactions with automatic savepoint handling

### 4. Streaming Results via Cursors

- `Database.Cursor<T>` implements AsyncSequence
- Memory-efficient for large result sets
- Connection held until iteration completes
- Actor-based iterator management for safety

### 5. Current API Surface

**Reader Protocol**:
- `read<T>(_ block:) -> T`
- `close()`

**Writer Protocol** (extends Reader):
- `write<T>(_ block:) -> T`

**Connection.Protocol** (query execution):
- `execute(Statement<()>)` - No return
- `execute(String)` - Raw SQL
- `executeFragment(QueryFragment)` - Low-level
- `fetchAll(Statement<V>)` - Multiple rows
- `fetchOne(Statement<V>)` - Single row
- `fetchCursor(Statement<V>)` - Streaming
- `withNestedTransaction(isolation:_:)`
- `withSavepoint(_:_:)`

**Writer Extensions** (transactions):
- `withTransaction(isolation:_:)`
- `withRollback(_:)`
- `withNestedTransaction(isolation:_:)`
- `withSavepoint(_:_:)`

### 6. Factory Methods

```swift
Database.pool(
    configuration: PostgresClient.Configuration,
    minConnections: Int = 2,
    maxConnections: Int = 20,
    logger: Logger? = nil
) -> ClientRunner

Database.singleConnection(
    configuration: PostgresClient.Configuration,
    logger: Logger? = nil
) -> ClientRunner
```

Both return `ClientRunner` (Pool and Queue are type aliases).

## LISTEN/NOTIFY Integration Points

### Recommended Location: ClientRunner Level

**Why**:
1. Can maintain dedicated LISTEN connection
2. Separate from query pool (doesn't consume connections)
3. Natural lifecycle integration with close()
4. Actor-safe through NotificationManager actor

**Design Pattern**:
```
ClientRunner
├── client: PostgresClient (query pool)
├── runTask: Task (manages client lifecycle)
└── notificationManager: NotificationManager (new)
    ├── Maintains: dedicated LISTEN connection
    ├── Manages: subscriber continuations per channel
    ├── Provides: subscribe(channel) -> AsyncStream<Notification>
    └── Provides: notify(channel, payload) -> throws
```

### Key Design Decisions for LISTEN/NOTIFY

1. **Separate Connection**: NotificationManager maintains its own connection, doesn't compete with query pool
2. **AsyncStream API**: Fits Swift async/await patterns used throughout the package
3. **Actor-Based**: Maintains strict concurrency guarantees
4. **Integration Point**: At ClientRunner, not Connection.Protocol (too low-level, connection-specific)
5. **Sendable**: All types fully Sendable for concurrency support

## File Structure to Create

```
Sources/Records/
├── Core/
│   └── Database.ClientRunner.swift       [MODIFY] Add NotificationManager
├── Notifications/                         [NEW]
│   ├── Database.Notification.swift       [NEW]
│   ├── Database.NotificationManager.swift [NEW]
│   └── Database.Writer+Notifications.swift [NEW]
└── exports.swift                         [MODIFY]
```

## Implementation Overview

### 1. Database.Notification (3-4 types)
```swift
public struct Notification: Sendable {
    public let channel: String
    public let payload: String
    public let pid: UInt32
}
```

### 2. Database.NotificationManager (50-60 lines)
Actor that manages:
- Single dedicated LISTEN connection
- Subscriber continuations per channel
- Background listening task
- Cleanup on close()

### 3. Database.Writer+Notifications (30-40 lines)
Public API extensions:
```swift
func subscribe(to channel: String) -> AsyncStream<Notification>
func notify(channel: String, payload: String) async throws
```

### 4. ClientRunner Modifications (20-30 lines)
- Add notificationManager property
- Initialize in init()
- Add public methods (delegate to manager)
- Update close() to clean up notifications

## API Design Patterns Used in Records

1. **Protocol-Based Architecture**: Reader/Writer protocols enable injection and testing
2. **Closure-Based Lending**: Connections borrowed and returned automatically
3. **Sendable Everywhere**: Full Swift 6 strict concurrency support
4. **Generic Results**: Type-safe return values from operations
5. **Async/Await First**: No callbacks, pure async/await
6. **AsyncSequence for Streaming**: Cursors and LISTEN/NOTIFY fit naturally
7. **Layered Abstraction**: Low-level (Connection.Protocol) → Mid-level (Statement) → High-level (Table.swift)

## Consistency with Existing Code

The recommended LISTEN/NOTIFY implementation:
- Uses same patterns (actors, AsyncStream, Sendable)
- Follows same documentation style
- Integrates with existing lifecycle management
- Doesn't break any existing APIs
- Fits with dependency injection pattern
- Maintains separation of concerns

## Testing Infrastructure

**Existing Support**:
- Schema isolation per test suite
- Parallel test execution capability
- `TestDatabase` for setup
- `withRollback()` for test isolation

**For LISTEN/NOTIFY Testing**:
- Mock NotificationManager in tests
- Use real notifications in integration tests
- RecordsTestSupport provides helpers

## Dependencies Used

- **postgres-nio** - PostgreSQL driver (already imported)
- **StructuredQueriesPostgres** - Query building (already imported)
- **Logging** - Already used in records
- No new dependencies required for LISTEN/NOTIFY

## Performance Characteristics

**Connection Usage**:
- LISTEN connection: 1 dedicated connection
- Query pool: minConnections to maxConnections (separate)
- Total = 1 + (pool size)

**Scalability**:
- One LISTEN connection handles unlimited subscribers (via AsyncStream)
- Multiple channels use same LISTEN connection
- NOTIFY uses regular pool connections (fast)

**Memory**:
- Continuations stored in dictionary per channel
- Cleaned up when subscriber cancels

## Documentation Quality

Records has excellent documentation:
- Comprehensive doc comments with examples
- Architecture decisions documented
- Usage patterns shown
- Error handling guidance included

LISTEN/NOTIFY implementation should follow same standards.

## Notable Constraints & Opportunities

**Current Constraints**:
1. No state stored in Connection after operation completes
2. Transactions block writer (exclusive)
3. Cursors are best-effort (no guaranteed transaction)
4. No direct connection access

**LISTEN/NOTIFY Opportunities**:
1. First async long-lived operation in Records
2. Can establish pattern for future streaming features
3. Enables real-time application patterns
4. Natural fit with async/await ecosystem

## Estimated Implementation Effort

**Core Implementation**: 2-3 hours
- Create Notification type
- Create NotificationManager actor
- Integrate with ClientRunner
- Create Writer extensions

**Testing**: 1-2 hours
- Add test support
- Create example tests
- Test error handling

**Documentation**: 1-2 hours
- API documentation
- Usage examples
- Troubleshooting guide

**Total**: 4-7 hours for production-ready implementation

## Success Criteria

A successful LISTEN/NOTIFY implementation should:
1. Use dedicated connection (doesn't interfere with queries)
2. Support multiple subscribers per channel
3. Use AsyncStream for clean API
4. Be fully Sendable (strict concurrency)
5. Integrate cleanly with ClientRunner lifecycle
6. Work with connection pooling
7. Have comprehensive documentation
8. Include examples and tests
9. Handle errors gracefully
10. Maintain performance characteristics

## Conclusion

The swift-records package is well-architected, lean, and follows consistent patterns. It provides a natural integration point for LISTEN/NOTIFY support via the ClientRunner, which manages the PostgresClient lifecycle.

The recommended approach maintains architectural consistency by:
- Using an actor for the NotificationManager
- Leveraging AsyncStream for the public API
- Maintaining Sendable guarantees
- Integrating with existing lifecycle management
- Keeping notification logic separate from query execution

This implementation will enable real-time notification patterns while preserving the clarity and simplicity that makes Records an excellent database abstraction layer.
