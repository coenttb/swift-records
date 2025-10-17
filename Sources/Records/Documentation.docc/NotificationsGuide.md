# PostgreSQL LISTEN/NOTIFY Support

Real-time database notifications with a delightful, type-safe Swift API.

## Overview

Swift-records provides first-class support for PostgreSQL's `LISTEN`/`NOTIFY` feature, allowing you to build reactive, real-time applications with minimal code. The API is built on Swift's modern concurrency features, making it feel natural and Swift-native.

## Quick Start

### Sending Notifications

```swift
// Simple string notification
try await db.notify(channel: "cache_invalidate")

// With a payload
try await db.notify(channel: "updates", payload: "New data available")

// Type-safe with Codable
struct ReminderChange: Codable {
    let id: Int
    let action: String
}

try await db.notify(
    channel: "reminders",
    payload: ReminderChange(id: 123, action: "updated")
)
```

### Receiving Notifications

```swift
// Simple string notifications
for try await notification in try await db.notifications(channel: "updates") {
    print("Update: \(notification.payload)")
}

// Type-safe notifications
for try await change: ReminderChange in try await db.notifications(channel: "reminders") {
    await updateUI(with: change)
}
```

## Real-World Example: Live Reminder Updates

This example shows how to build a real-time reminder system where UI updates happen automatically when any client modifies a reminder.

### Step 1: Set Up Type-Safe Notification Channel

```swift
// Define a schema that couples table and notifications
struct ReminderNotifications: Database.Notification.ChannelSchema {
    typealias TableType = Reminder  // ← Compile-time table coupling!

    struct Payload: Codable, Sendable {
        let operation: String  // "INSERT", "UPDATE", or "DELETE"
        let new: Reminder?
    }

    // channelName auto-derived as "reminders_notifications"
    // Override only if needed: static let channelName = "reminder_changes"
}

// Set up the notification trigger in a migration
let migrator = Database.Migrator()

migrator.register("reminder_notifications") { db in
    try await db.setupNotificationChannel(
        schema: ReminderNotifications.self,  // ← Table derived from schema!
        on: .insert, .update, .delete
    )
}

try await migrator.migrate(db)
```

**Why this approach is superior:**
- ✅ No string literals - channel name derived from table
- ✅ Impossible to mix up table and channel types
- ✅ Compile-time guarantee of correct table-channel pairing

### Step 2: Listen for Changes

```swift
@MainActor
class ReminderViewModel: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Dependency(\.defaultDatabase) var db

    private var notificationTask: Task<Void, Never>?

    func startListening() {
        notificationTask = Task {
            do {
                for try await change: ReminderChange in try await db.notifications(
                    channel: "reminder_changes"
                ) {
                    await handleChange(change)
                }
            } catch {
                print("Notification error: \(error)")
            }
        }
    }

    func stopListening() {
        notificationTask?.cancel()
        notificationTask = nil
    }

    private func handleChange(_ change: ReminderChange) async {
        switch change.operation {
        case "INSERT", "UPDATE":
            // Use the reminder from the notification payload
            if let updated = change.new {
                if let index = reminders.firstIndex(where: { $0.id == updated.id }) {
                    reminders[index] = updated
                } else {
                    reminders.append(updated)
                }
            }

        case "DELETE":
            // For DELETE operations, change.new is nil, but we can still identify the record
            // In a real app, you might want to include the ID in a separate field
            if let deleted = change.new {
                reminders.removeAll { $0.id == deleted.id }
            }

        default:
            break
        }
    }
}
```

## Advanced Usage

### Multiple Channels

Listen to notifications from multiple channels simultaneously:

```swift
for try await notification in try await db.notifications(
    channels: ["reminders", "todos", "lists"]
) {
    switch notification.channel {
    case "reminders":
        await handleReminderChange(notification.payload)
    case "todos":
        await handleTodoChange(notification.payload)
    case "lists":
        await handleListChange(notification.payload)
    default:
        break
    }
}
```

### With Timeout

Use structured concurrency to add timeouts:

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    // Timeout task
    group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw TimeoutError()
    }

    // Notification listener
    group.addTask {
        for try await notification in try await db.notifications(channel: "updates") {
            await handleUpdate(notification)
        }
    }

    // Wait for first to complete
    try await group.next()
    group.cancelAll()  // Cancel the other
}
```

### Within Transactions

Notifications sent within a transaction are only delivered after the transaction commits:

```swift
try await db.withTransaction { db in
    // Update reminder
    try await Reminder.update { $0.completed = true }
        .where { $0.id == reminderId }
        .execute(db)

    // Notify listeners - only sent if transaction succeeds
    try await db.notify(
        channel: "reminders",
        payload: ReminderChange(id: reminderId, action: "completed")
    )
}
```

## Cache Invalidation Pattern

A common use case is cache invalidation:

```swift
actor CacheManager {
    private var cache: [String: Data] = [:]

    func start(database: any Database.Reader) {
        Task {
            for try await _ in try await database.notifications(channel: "cache_invalidate") {
                await invalidateAll()
            }
        }
    }

    func invalidateAll() {
        cache.removeAll()
    }

    func get(_ key: String) -> Data? {
        cache[key]
    }

    func set(_ key: String, value: Data) {
        cache[key] = value
    }
}

// In your API
try await db.write { db in
    try await Record.update { ... }.execute(db)

    // Invalidate caches across all servers
    try await db.notify(channel: "cache_invalidate")
}
```

## Connection Management

The notification system automatically manages connections:

- A dedicated connection is acquired when you start listening
- The connection is held open for the duration of the AsyncSequence
- `LISTEN` commands are executed automatically
- `UNLISTEN` commands are executed when the sequence ends
- The connection is returned to the pool when you stop listening
- Cancellation is handled gracefully

## Error Handling

```swift
do {
    for try await change: ReminderChange in try await db.notifications(channel: "reminders") {
        await handleChange(change)
    }
} catch Database.Error.notificationDecodingFailed(let type, let payload, let error) {
    print("Failed to decode \(type) from: \(payload)")
    print("Error: \(error)")
} catch Database.Error.notificationNotSupported(let message) {
    print("Notifications not supported: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Testing

The API is designed to be testable. In tests, you can use the same notification API:

```swift
@Test("Notifications work in tests")
func testNotifications() async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for try await notification in try await db.notifications(channel: "test") {
                #expect(notification.payload == "test data")
                break
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        try await db.notify(channel: "test", payload: "test data")

        try await group.next()
        group.cancelAll()
    }
}
```

## Best Practices

### 1. Use Type-Safe Notifications

Always prefer typed notifications over raw strings:

```swift
// ✅ Good
struct Event: Codable { let type: String, data: String }
try await db.notify(channel: "events", payload: event)

// ❌ Avoid
try await db.notify(channel: "events", payload: "{\"type\":\"update\"}")
```

### 2. Handle Cancellation

Always ensure your notification listeners can be cancelled:

```swift
class MyService {
    private var listenerTask: Task<Void, Never>?

    func start() {
        listenerTask = Task {
            for try await notification in try await db.notifications(channel: "updates") {
                await handle(notification)
            }
        }
    }

    func stop() {
        listenerTask?.cancel()  // ✅ Clean cancellation
    }
}
```

### 3. Use Dedicated Channels

Create specific channels for different notification types:

```swift
// ✅ Good - specific channels
"reminder_created"
"reminder_updated"
"reminder_deleted"

// ❌ Avoid - generic channels that require payload parsing
"reminders"  // What changed? Created, updated, deleted?
```

### 4. Document Your Notification Schema

Document the shape of notifications in your codebase:

```swift
/// Notification sent when a reminder changes.
///
/// **Channel**: `reminder_changes`
///
/// **Payload**:
/// ```json
/// {
///     "id": 123,
///     "action": "INSERT" | "UPDATE" | "DELETE",
///     "title": "string"
/// }
/// ```
struct ReminderChange: Codable {
    let id: Int
    let action: String
    let title: String
}
```

## Performance Considerations

- **Connection Pooling**: Each listener holds a connection from the pool. Plan your pool size accordingly.
- **Buffering**: Notifications are buffered with an unbounded policy to ensure none are dropped.
- **Payload Size**: Keep notification payloads small. For large data, send an ID and fetch details separately.
- **Channel Count**: PostgreSQL can handle many channels efficiently, but each `LISTEN` requires network round-trip.

## Comparison with Other Approaches

| Approach | Latency | Complexity | Scalability |
|----------|---------|------------|-------------|
| Polling | High (seconds) | Low | Poor (database load) |
| **LISTEN/NOTIFY** | **Low (milliseconds)** | **Medium** | **Excellent** |
| External Queue | Low | High | Excellent |

LISTEN/NOTIFY is the sweet spot for PostgreSQL-based applications: real-time updates without external dependencies.

## Topics

### Essentials

- ``Database/NotificationStream``
- ``Database/Notification``

### Sending Notifications

- ``Database/Writer/notify(channel:payload:)-5ljww``
- ``Database/Writer/notify(channel:payload:encoder:)``
- ``Database/Writer/notify(channel:)``

### Receiving Notifications

- ``Database/Reader/notifications(channel:as:decoder:)``
- ``Database/Reader/notifications(channel:decoder:)``
- ``Database/Reader/notifications(schema:decoder:)``

### Error Handling

- ``Database/Error/invalidNotificationChannels(_:)``
- ``Database/Error/notificationNotSupported(_:)``
- ``Database/Error/invalidNotificationPayload(_:)``
- ``Database/Error/notificationDecodingFailed(type:payload:underlying:)``
