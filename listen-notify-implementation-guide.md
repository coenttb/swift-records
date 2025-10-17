# LISTEN/NOTIFY Implementation Guide for Swift-Records

## Architecture Overview

### Challenge: Connection Pooling vs. LISTEN/NOTIFY

PostgreSQL's LISTEN/NOTIFY mechanism requires:
1. A persistent connection to stay subscribed
2. Ability to receive asynchronous notifications from the server
3. Connection cannot be used for other operations while listening

However, Records uses connection pooling where connections are:
1. Returned to the pool after each operation
2. Reused by different operations
3. Not tied to specific client operations

**Solution**: Implement a dedicated notification manager that:
- Maintains separate connections for LISTEN operations
- Routes notifications to multiple subscribers
- Integrates with the ClientRunner lifecycle
- Uses AsyncStream for clean async/await API

## Recommended Implementation Strategy

### 1. Create Notification Types (New File)

**Location**: `Sources/Records/Notifications/Database.Notification.swift`

```swift
import Foundation
import PostgresNIO

extension Database {
    /// A notification received from PostgreSQL.
    public struct Notification: Sendable {
        /// The channel name on which the notification was received.
        public let channel: String
        
        /// The payload data (if any).
        public let payload: String
        
        /// PID of the backend that sent the notification.
        public let pid: UInt32
        
        package init(from notificationResponse: NotificationResponse) {
            self.channel = notificationResponse.channel
            self.payload = notificationResponse.payload
            self.pid = notificationResponse.pid
        }
    }
}
```

### 2. Create Notification Manager Actor (New File)

**Location**: `Sources/Records/Notifications/Database.NotificationManager.swift`

Key responsibilities:
- Maintain a dedicated LISTEN connection
- Track active subscribers per channel
- Route incoming notifications to subscribers
- Handle connection failures and reconnection
- Clean lifecycle with parent ClientRunner

```swift
import Foundation
import PostgresNIO
import Logging

extension Database {
    /// Manages PostgreSQL LISTEN/NOTIFY subscriptions.
    ///
    /// This actor maintains a dedicated connection for LISTEN operations
    /// and routes notifications to multiple subscribers using AsyncStream.
    package actor NotificationManager {
        private let client: PostgresClient
        private var listenConnection: PostgresConnection?
        private var subscribers: [String: [AsyncStream<Notification>.Continuation]] = [:]
        private var listenTask: Task<Void, Never>?
        private let logger: Logger
        
        package init(client: PostgresClient, logger: Logger) {
            self.client = client
            self.logger = logger
        }
        
        /// Subscribe to notifications on a channel.
        ///
        /// Multiple subscribers can listen to the same channel.
        /// Each subscriber receives all notifications independently.
        package func subscribe(to channel: String) -> AsyncStream<Notification> {
            AsyncStream { continuation in
                Task {
                    // Register the subscriber
                    if self.subscribers[channel] == nil {
                        self.subscribers[channel] = []
                        // Start LISTEN for this channel
                        await self.registerChannel(channel)
                    }
                    self.subscribers[channel]?.append(continuation)
                }
            }
        }
        
        /// Send a notification on a channel.
        ///
        /// Uses a regular query connection from the pool.
        package func notify(
            channel: String,
            payload: String
        ) async throws {
            try await client.withConnection { connection in
                let notification = "NOTIFY \(channel), '\(payload.replacingOccurrences(of: "'", with: "''"))'"
                let query = PostgresQuery(unsafeSQL: notification)
                _ = try await connection.query(query)
            }
        }
        
        /// Clean up all subscriptions and close the listen connection.
        package func close() async throws {
            listenTask?.cancel()
            if let listenConnection = self.listenConnection {
                try await listenConnection.close()
            }
        }
        
        // MARK: - Private Implementation
        
        private func registerChannel(_ channel: String) async {
            // Ensure listen connection is established
            if listenConnection == nil {
                do {
                    listenConnection = try await client.makeConnection()
                    startListeningTask()
                } catch {
                    logger.error("Failed to create listen connection: \(error)")
                }
            }
            
            // Execute LISTEN command
            guard let listenConnection = listenConnection else { return }
            do {
                let query = PostgresQuery(unsafeSQL: "LISTEN \(channel)")
                _ = try await listenConnection.query(query)
            } catch {
                logger.error("Failed to LISTEN on \(channel): \(error)")
            }
        }
        
        private func startListeningTask() {
            listenTask = Task {
                guard let listenConnection = self.listenConnection else { return }
                
                do {
                    // Listen for notifications
                    for try await notification in listenConnection.notifications {
                        let databaseNotification = Database.Notification(
                            from: notification
                        )
                        
                        // Route to subscribers
                        if let continuations = self.subscribers[databaseNotification.channel] {
                            for continuation in continuations {
                                continuation.yield(databaseNotification)
                            }
                        }
                    }
                } catch {
                    logger.error("Error in notification listener: \(error)")
                }
            }
        }
    }
}
```

### 3. Integrate with ClientRunner (Modify Existing File)

**Location**: `Sources/Records/Core/Database.ClientRunner.swift`

Add to the `ClientRunner` class:

```swift
// Add this property
private let notificationManager: NotificationManager?

// Modify init to create the notification manager
public init(client: PostgresClient, startRunTask: Bool = true) async {
    self.client = client
    self.notificationManager = NotificationManager(client: client, logger: logger)
    
    // ... existing code ...
}

// Add public API methods
public func subscribe(to channel: String) -> AsyncStream<Database.Notification> {
    notificationManager?.subscribe(to: channel) ?? .init { _ in }
}

public func notify(
    channel: String,
    payload: String
) async throws {
    try await notificationManager?.notify(channel: channel, payload: payload)
}

// Update close() to clean up notifications
public func close() async throws {
    try await notificationManager?.close()
    runTask.cancel()
    try await client.close()
}
```

### 4. Expose at Reader/Writer Protocol Level (New File)

**Location**: `Sources/Records/Notifications/Database.Writer+Notifications.swift`

```swift
import Foundation

extension Database.Writer {
    /// Subscribe to notifications on a channel.
    ///
    /// Returns an AsyncStream that yields notifications as they arrive.
    /// The subscription is active until the stream is cancelled or completed.
    ///
    /// ```swift
    /// @Dependency(\.defaultDatabase) var db
    ///
    /// // Listen for user events
    /// for try await notification in db.subscribe(to: "user_events") {
    ///     await handleUserEvent(notification.payload)
    /// }
    /// ```
    public func subscribe(to channel: String) -> AsyncStream<Database.Notification> {
        // For ClientRunner specifically
        if let clientRunner = self as? ClientRunner {
            return clientRunner.subscribe(to: channel)
        }
        
        // For other implementations, return empty stream
        return .init { _ in }
    }
    
    /// Send a notification on a channel.
    ///
    /// ```swift
    /// try await db.notify(on: "user_events", payload: "user_123_updated")
    /// ```
    public func notify(
        channel: String,
        payload: String
    ) async throws {
        if let clientRunner = self as? ClientRunner {
            try await clientRunner.notify(channel: channel, payload: payload)
        }
    }
}
```

### 5. Add Error Handling

Extend `Database.Error` in `Sources/Records/Core/Database.Error.swift`:

```swift
/// Failed to establish notification listener.
case notificationListenerFailed(underlyingError: Swift.Error)

/// Notification channel name is invalid.
case invalidNotificationChannel(name: String)
```

### 6. Create Test Support (New File)

**Location**: `Sources/RecordsTestSupport/Database+NotificationTestSupport.swift`

```swift
import Foundation
import Records

extension Database {
    /// A notification manager that collects notifications for testing.
    package class TestNotificationManager: Sendable {
        private let notifications = NSMutableArray()
        
        package func recordNotification(_ notification: Database.Notification) {
            notifications.add(notification)
        }
        
        package func allNotifications() -> [Database.Notification] {
            notifications.array as? [Database.Notification] ?? []
        }
        
        package func clear() {
            notifications.removeAllObjects()
        }
    }
}
```

### 7. Update exports.swift

**Location**: `Sources/Records/exports.swift`

```swift
@_exported import Dependencies
@_exported import PostgresNIO
@_exported import StructuredQueriesPostgres

// Re-export Notification type
extension Database {
    public typealias Notification = Database.Notification
}
```

## File Organization

```
Sources/Records/
├── Core/
│   └── Database.ClientRunner.swift       # [MODIFY] Add notification manager
├── Notifications/                         # [NEW] Create directory
│   ├── Database.Notification.swift       # [NEW] Notification type
│   ├── Database.NotificationManager.swift # [NEW] Manager actor
│   └── Database.Writer+Notifications.swift # [NEW] Writer extensions
└── exports.swift                         # [MODIFY] Re-export types
```

## API Usage Examples

### Basic Subscription

```swift
@Dependency(\.defaultDatabase) var db

// Subscribe to a channel
let stream = db.subscribe(to: "user_events")

// Process notifications as they arrive
for try await notification in stream {
    print("Channel: \(notification.channel)")
    print("Payload: \(notification.payload)")
}
```

### Multiple Subscribers

```swift
// Two subscribers on same channel both receive notifications
let stream1 = db.subscribe(to: "orders")
let stream2 = db.subscribe(to: "orders")

async let _: Void = {
    for try await notif in stream1 {
        print("Subscriber 1: \(notif.payload)")
    }
}()

async let _: Void = {
    for try await notif in stream2 {
        print("Subscriber 2: \(notif.payload)")
    }
}()
```

### Send Notifications

```swift
// Trigger a notification from within app logic
try await db.write { db in
    try await User.insert { ... }.execute(db)
    // Notify subscribers
    try await db.notify(on: "user_events", payload: "user_created")
}
```

### Database Connection

```swift
// Notifications work with pooled connections
let db = try await Database.pool(
    configuration: config,
    minConnections: 5,
    maxConnections: 20
)

// Notifications use separate connection internally
let notifications = db.subscribe(to: "channel")

// Regular queries use pool connections
try await db.read { db in
    let users = try await User.fetchAll(db)
}
```

## Integration Considerations

### 1. Lifecycle Management

- NotificationManager is created with ClientRunner
- Cleaned up when ClientRunner.close() is called
- Listen connection separate from query pool

### 2. Error Recovery

- Connection failures automatically handled
- Subscribers notified on critical errors (optional enhancement)
- Graceful degradation if LISTEN fails

### 3. Testing

- Test mode can mock notifications
- Schema isolation still works (tests use same database)
- No special setup needed for notification tests

### 4. Performance

- Dedicated connection for LISTEN (doesn't block queries)
- AsyncStream for lazy evaluation
- No polling required

### 5. Sendability

- NotificationManager is actor (Sendable)
- Notification is Sendable
- AsyncStream is Sendable
- Full strict concurrency support

## Migration Path

### Phase 1: Core Implementation
1. Add Notification type
2. Add NotificationManager actor
3. Integrate with ClientRunner
4. Create test support

### Phase 2: Public API
1. Add Writer extensions
2. Update exports
3. Add documentation

### Phase 3: Testing
1. Add test utilities
2. Add example code
3. Document best practices

### Phase 4: Documentation
1. Update README
2. Add tutorials
3. Add troubleshooting guide

## Known Limitations & Future Work

### Current Design
- LISTEN notifications are async streams (one-way)
- No built-in request-response patterns
- No pattern matching on channels (PostgreSQL feature available)

### Future Enhancements
1. Support UNLISTEN to unsubscribe from channels
2. Support wildcard subscriptions (if PostgreSQL adds)
3. Add built-in retry/reconnection for listen connections
4. Add metrics for notification throughput
5. Support for notification payloads (JSON parsing helpers)

## Compatibility Notes

- Works with PostgreSQL 9.0+ (LISTEN/NOTIFY available)
- Compatible with all connection pool configurations
- Thread-safe for use in async contexts
- No breaking changes to existing API
