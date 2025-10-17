# LISTEN/NOTIFY Code Examples and Best Practices

## Real-World Usage Patterns

### 1. Real-Time Notifications for Entity Updates

```swift
// Subscriber (e.g., in a view model or service)
@MainActor
class OrderService {
    @Dependency(\.defaultDatabase) var db
    
    func watchOrderStatus(orderId: String) -> AsyncStream<Order> {
        AsyncStream { continuation in
            Task {
                // Get initial order
                let initialOrder = try await db.read { db in
                    try await Order.filter { $0.id == orderId }.fetchOne(db)
                }
                if let order = initialOrder {
                    continuation.yield(order)
                }
                
                // Listen for changes
                for try await notification in db.subscribe(to: "order_\(orderId)") {
                    // Parse payload to get updated order
                    if let order = try await db.read({ db in
                        try await Order.filter { $0.id == orderId }.fetchOne(db)
                    }) {
                        continuation.yield(order)
                    }
                }
            }
        }
    }
}

// Publisher (e.g., in an update handler)
class OrderRepository {
    @Dependency(\.defaultDatabase) var db
    
    func updateOrderStatus(orderId: String, status: Order.Status) async throws {
        try await db.write { db in
            try await Order
                .filter { $0.id == orderId }
                .update { $0.status = status }
                .execute(db)
            
            // Notify subscribers
            try await db.notify(
                on: "order_\(orderId)",
                payload: "status_changed:\(status.rawValue)"
            )
        }
    }
}

// Usage in UI
@Main
struct OrderTrackerView: View {
    @Dependency(\.defaultDatabase) var db
    @State var order: Order?
    
    var body: some View {
        if let order = order {
            Text("Status: \(order.status)")
                .onReceive(
                    Publishers.AsyncStream(
                        OrderService().watchOrderStatus(orderId: order.id)
                    ),
                    perform: { self.order = $0 }
                )
        }
    }
}
```

### 2. Broadcast to Multiple Users

```swift
// Service that broadcasts events
class UserActivityService {
    @Dependency(\.defaultDatabase) var db
    
    func notifyUserOnline(userId: String) async throws {
        try await db.write { db in
            try await User
                .filter { $0.id == userId }
                .update { $0.isOnline = true; $0.lastSeen = Date() }
                .execute(db)
            
            // Broadcast to all subscribers
            try await db.notify(
                on: "user_activity",
                payload: "user_\(userId)_online"
            )
        }
    }
    
    func watchUserActivity() -> AsyncStream<String> {
        db.subscribe(to: "user_activity")
            .map { $0.payload }
    }
}

// Usage - multiple services listening to same channel
Task {
    for try await activity in UserActivityService().watchUserActivity() {
        print("User activity: \(activity)")
    }
}

Task {
    for try await activity in UserActivityService().watchUserActivity() {
        await updateUserList()
    }
}
```

### 3. Transactional Safety with NOTIFY

```swift
class PaymentProcessor {
    @Dependency(\.defaultDatabase) var db
    
    func processPayment(orderId: String, amount: Decimal) async throws {
        try await db.withTransaction(isolation: .serializable) { db in
            // Check order exists and isn't already processed
            guard let order = try await Order
                .filter { $0.id == orderId && $0.status == .pending }
                .fetchOne(db) else {
                throw PaymentError.orderNotFound
            }
            
            // Process payment (in real app, call payment gateway)
            let transactionId = UUID().uuidString
            
            // Record payment
            try await Payment.insert {
                ($0.orderId, $0.amount, $0.transactionId, $0.status)
            } values: {
                (orderId, amount, transactionId, .completed)
            }.execute(db)
            
            // Update order
            try await Order
                .filter { $0.id == orderId }
                .update { $0.status = .paid }
                .execute(db)
            
            // Notify after transaction commits
            try await db.notify(
                on: "payment_completed",
                payload: orderId
            )
        }
    }
}
```

### 4. Cascading Notifications

```swift
class InventoryService {
    @Dependency(\.defaultDatabase) var db
    
    func updateInventory(productId: String, quantity: Int) async throws {
        try await db.write { db in
            try await Product
                .filter { $0.id == productId }
                .update { $0.quantity -= quantity }
                .execute(db)
            
            // Notify about inventory change
            try await db.notify(
                on: "inventory_changed",
                payload: productId
            )
            
            // Check if low stock, notify separately
            if let product = try await Product
                .filter { $0.id == productId }
                .fetchOne(db),
               product.quantity < 10 {
                try await db.notify(
                    on: "low_stock_alert",
                    payload: productId
                )
            }
        }
    }
}

// Multiple handlers can react to notifications
Task {
    // Handler 1: Update UI
    for try await notification in db.subscribe(to: "inventory_changed") {
        await updateProductDisplay(notification.payload)
    }
}

Task {
    // Handler 2: Trigger reorder
    for try await notification in db.subscribe(to: "low_stock_alert") {
        try await reorderProduct(notification.payload)
    }
}
```

### 5. Combining Multiple Notification Streams

```swift
class DashboardService {
    @Dependency(\.defaultDatabase) var db
    
    func watchAllEvents() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                // Combine multiple notification streams
                let ordersTask = Task {
                    for try await notif in db.subscribe(to: "order_events") {
                        continuation.yield(.order(notif.payload))
                    }
                }
                
                let paymentsTask = Task {
                    for try await notif in db.subscribe(to: "payment_events") {
                        continuation.yield(.payment(notif.payload))
                    }
                }
                
                let usersTask = Task {
                    for try await notif in db.subscribe(to: "user_events") {
                        continuation.yield(.user(notif.payload))
                    }
                }
                
                _ = await [ordersTask.result, paymentsTask.result, usersTask.result]
            }
        }
    }
    
    enum Event {
        case order(String)
        case payment(String)
        case user(String)
    }
}
```

## Best Practices

### 1. Channel Naming Conventions

```swift
// Good: Clear, hierarchical naming
db.subscribe(to: "user_123_profile_updated")
db.subscribe(to: "order_456_status_changed")
db.subscribe(to: "inventory_product_789_low_stock")

// Good: Broadcast channels
db.subscribe(to: "system_alerts")
db.subscribe(to: "user_activity")

// Avoid: Generic or ambiguous names
db.subscribe(to: "event")
db.subscribe(to: "update")
```

### 2. Payload Structures

```swift
// Simple payload
try await db.notify(on: "user_updated", payload: userId)

// JSON payload for complex data
let payload = try JSONEncoder().encode([
    "userId": userId,
    "action": "profile_updated",
    "timestamp": ISO8601DateFormatter().string(from: Date())
])
try await db.notify(
    on: "user_events",
    payload: String(data: payload, encoding: .utf8) ?? ""
)

// Parse on receiver side
for try await notification in db.subscribe(to: "user_events") {
    if let data = notification.payload.data(using: .utf8),
       let event = try JSONDecoder().decode(UserEvent.self, from: data) {
        await handleUserEvent(event)
    }
}
```

### 3. Lifecycle Management

```swift
// Proper cleanup
class NotificationListener {
    private var task: Task<Void, Never>?
    @Dependency(\.defaultDatabase) var db
    
    func startListening() {
        task = Task {
            for try await notification in db.subscribe(to: "events") {
                await handleNotification(notification)
            }
        }
    }
    
    func stopListening() {
        task?.cancel()
        task = nil
    }
    
    deinit {
        stopListening()
    }
}

// Ensure cleanup in async context
Task {
    let stream = db.subscribe(to: "events")
    defer { /* stream automatically cleaned up */ }
    
    for try await notification in stream {
        await process(notification)
    }
}
```

### 4. Error Handling

```swift
class RobustNotificationHandler {
    @Dependency(\.defaultDatabase) var db
    
    func listenWithRetry(
        channel: String,
        maxRetries: Int = 3
    ) async {
        var retryCount = 0
        
        while retryCount < maxRetries {
            do {
                for try await notification in db.subscribe(to: channel) {
                    await handleNotification(notification)
                    retryCount = 0 // Reset on success
                }
            } catch {
                retryCount += 1
                if retryCount < maxRetries {
                    // Exponential backoff
                    let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    print("Failed to subscribe after \(maxRetries) retries")
                    return
                }
            }
        }
    }
}
```

### 5. Testing Notifications

```swift
// Test helper
class NotificationTestHelper {
    @Dependency(\.defaultDatabase) var db
    
    func testNotification() async throws {
        var receivedNotifications: [Database.Notification] = []
        
        // Start listening in background
        let listenerTask = Task {
            for try await notification in db.subscribe(to: "test_channel") {
                receivedNotifications.append(notification)
                if receivedNotifications.count >= 1 {
                    break
                }
            }
        }
        
        // Give subscriber time to register
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Send notification
        try await db.notify(on: "test_channel", payload: "test_payload")
        
        // Wait for listener
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        listenerTask.cancel()
        
        // Verify
        #expect(receivedNotifications.count == 1)
        #expect(receivedNotifications.first?.payload == "test_payload")
    }
}

// In test suite
@Suite("Notifications")
struct NotificationTests {
    @Dependency(\.defaultDatabase) var db
    
    @Test
    func testNotificationDelivery() async throws {
        try await NotificationTestHelper().testNotification()
    }
}
```

## Performance Considerations

### 1. Connection Count

```swift
// Each subscription uses a connection from the dedicated pool
// Only one LISTEN connection needed (reused for multiple subscriptions)

// This is efficient:
let stream1 = db.subscribe(to: "channel_1")
let stream2 = db.subscribe(to: "channel_2")
let stream3 = db.subscribe(to: "channel_3")
// Uses 1 connection for LISTEN + regular query pool for NOTIFY

// Not necessary:
let connectionPool = try await Database.pool(
    configuration: config,
    minConnections: 20,
    maxConnections: 50
)
// LISTEN uses separate connection, doesn't consume pool
```

### 2. Payload Size

```swift
// PostgreSQL LISTEN/NOTIFY has limits:
// - Payload limit: 8KB (configurable)
// - Message is lost if client buffer full

// Good: Small, focused payloads
try await db.notify(on: "user_updated", payload: userId)

// Avoid: Large payloads
let largeData = try JSONEncoder().encode(entireUserObject) // Could be large
try await db.notify(on: "user_updated", payload: largePayload)
// Better: Send ID, fetch data in subscriber
```

### 3. Channel Subscription Efficiency

```swift
// Single subscription for multiple related channels
class InventoryService {
    @Dependency(\.defaultDatabase) var db
    
    func watchAllInventory() -> AsyncStream<InventoryEvent> {
        AsyncStream { continuation in
            Task {
                for try await notification in db.subscribe(to: "inventory") {
                    if let event = parse(notification.payload) {
                        continuation.yield(event)
                    }
                }
            }
        }
    }
}

// Instead of:
db.subscribe(to: "inventory_product_1")
db.subscribe(to: "inventory_product_2")
db.subscribe(to: "inventory_product_3")
// Use: db.subscribe(to: "inventory") with filtering
```

## Migration from Other Systems

### From Polling

```swift
// Before: Polling
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    Task {
        let orders = try await db.read { db in
            try await Order.filter { $0.status == .pending }.fetchAll(db)
        }
        // Process orders
    }
}

// After: LISTEN/NOTIFY
Task {
    for try await notification in db.subscribe(to: "new_orders") {
        let orders = try await db.read { db in
            try await Order.filter { $0.status == .pending }.fetchAll(db)
        }
        // Process orders
    }
}
```

### From Message Queues

```swift
// If using separate message queue (RabbitMQ, Kafka):

// Instead of:
let amqp = AMQPConnection()
for message in amqp.consume("queue.orders") {
    try await processOrder(message)
}

// Can use database as simpler queue:
class OrderQueue {
    @Dependency(\.defaultDatabase) var db
    
    func watchNewOrders() -> AsyncStream<Order> {
        db.subscribe(to: "new_orders")
            .asyncMap { _ in
                try await db.read { db in
                    try await Order.filter { $0.status == .pending }.fetchAll(db)
                }
            }
    }
}
```

## Troubleshooting

### 1. Notifications Not Received

```swift
// Issue: Channel name mismatch
try await db.notify(on: "user_updated", payload: "...")
// vs
for notification in db.subscribe(to: "user_update") { } // Typo!

// Solution: Use constants
struct NotificationChannels {
    static let userUpdated = "user_updated"
    static let orderCreated = "order_created"
}

try await db.notify(on: NotificationChannels.userUpdated, payload: "...")
for notification in db.subscribe(to: NotificationChannels.userUpdated) { }
```

### 2. Connection Issues

```swift
// Issue: Listen connection drops
// Solution: Implement retry logic (see Error Handling section)

// Issue: Too many connections
// Solution: Verify using:
// SELECT count(*) FROM pg_stat_activity WHERE state = 'listening';
```

### 3. Memory Leaks

```swift
// Incorrect: Task not cancelled
let task = Task {
    for try await notification in db.subscribe(to: "channel") {
        await process(notification)
    }
}
// task never cancelled -> stream never cleaned up

// Correct: Cancel when done
var task: Task<Void, Never>?

func startListening() {
    task = Task {
        for try await notification in db.subscribe(to: "channel") {
            await process(notification)
        }
    }
}

func stopListening() {
    task?.cancel()
}

deinit {
    stopListening()
}
```
