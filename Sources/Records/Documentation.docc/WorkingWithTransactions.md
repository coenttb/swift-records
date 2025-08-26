# Working with Transactions

Learn how to use transactions for atomic database operations and data consistency.

## What Are Transactions?

Transactions ensure that a group of database operations either all succeed or all fail together. This maintains data consistency even when errors occur.

## Basic Transactions

Use `withTransaction` to wrap multiple operations:

```swift
struct AccountService {
    @Dependency(\.defaultDatabase) var db
    
    func transferMoney(from: Int, to: Int, amount: Decimal) async throws {
        try await db.withTransaction { db in
            // Deduct from source account
            try await Account
                .filter { $0.id == from }
                .update { $0.balance -= amount }
                .execute(db)
            
            // Add to destination account
            try await Account
                .filter { $0.id == to }
                .update { $0.balance += amount }
                .execute(db)
            
            // Both operations succeed or both are rolled back
        }
    }
}
```

If any operation fails, all changes are rolled back automatically.

## Isolation Levels

Control how transactions interact with concurrent operations:

### Read Committed (Default)

Best for most applications:

```swift
try await db.withTransaction { db in
    // Uses PostgreSQL's default READ COMMITTED
    // Sees committed changes from other transactions
}
```

### Serializable

For critical operations requiring complete isolation:

```swift
try await db.withTransaction(isolation: .serializable) { db in
    // Complete isolation - may cause serialization errors
    let balance = try await Account
        .filter { $0.id == accountId }
        .fetchOne(db)
    
    guard let balance, balance.amount >= withdrawAmount else {
        throw InsufficientFunds()
    }
    
    try await Account
        .filter { $0.id == accountId }
        .update { $0.amount -= withdrawAmount }
        .execute(db)
}
```

### Repeatable Read

For consistent reads throughout the transaction:

```swift
try await db.withTransaction(isolation: .repeatableRead) { db in
    // All reads see the same snapshot
    let initialCount = try await User.fetchCount(db)
    
    // ... other operations ...
    
    let finalCount = try await User.fetchCount(db)
    // finalCount sees the same data as initialCount
}
```

## Savepoints

Use savepoints for nested transaction-like behavior:

```swift
try await db.withTransaction { db in
    // Main transaction starts
    try await User.insert { ... }.execute(db)
    
    // Try a risky operation with a savepoint
    do {
        try await db.withSavepoint("risky_operation") { db in
            try await riskyOperation(db)
        }
    } catch {
        // Only the savepoint is rolled back
        print("Risky operation failed, continuing...")
    }
    
    // Main transaction continues
    try await Post.insert { ... }.execute(db)
}
```

## Common Patterns

### Creating Related Records

```swift
func createUserWithProfile(
    name: String,
    email: String,
    bio: String
) async throws -> (User, Profile) {
    try await db.withTransaction { db in
        // Create user
        let user = try await User.insert {
            User.Draft(
                name: name,
                email: email,
                createdAt: Date()
            )
        }
        .returning(\.self)
        .fetchOne(db)!
        
        // Create profile using user's ID
        let profile = try await Profile.insert {
            Profile.Draft(
                userId: user.id,
                bio: bio,
                createdAt: Date()
            )
        }
        .returning(\.self)
        .fetchOne(db)!
        
        return (user, profile)
    }
}
```

### Conditional Rollback

```swift
func processOrder(orderId: Int) async throws {
    try await db.withTransaction { db in
        // Get order
        let order = try await Order
            .filter { $0.id == orderId }
            .fetchOne(db)
        
        guard let order else {
            throw OrderError.notFound
        }
        
        // Check inventory
        for item in order.items {
            let stock = try await Inventory
                .filter { $0.productId == item.productId }
                .fetchOne(db)
            
            guard let stock, stock.quantity >= item.quantity else {
                // Transaction will roll back
                throw OrderError.insufficientStock(item.productId)
            }
            
            // Update inventory
            try await Inventory
                .filter { $0.productId == item.productId }
                .update { $0.quantity -= item.quantity }
                .execute(db)
        }
        
        // Update order status
        try await Order
            .filter { $0.id == orderId }
            .update { $0.status = "processed" }
            .execute(db)
    }
}
```

### Handling Serialization Errors

```swift
func withdrawWithRetry(
    accountId: Int,
    amount: Decimal,
    maxAttempts: Int = 3
) async throws {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            try await db.withTransaction(isolation: .serializable) { db in
                let account = try await Account
                    .filter { $0.id == accountId }
                    .fetchOne(db)
                
                guard let account, account.balance >= amount else {
                    throw BankingError.insufficientFunds
                }
                
                try await Account
                    .filter { $0.id == accountId }
                    .update { $0.balance -= amount }
                    .execute(db)
            }
            return // Success
        } catch {
            lastError = error
            if isSerializationError(error) && attempt < maxAttempts {
                // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(attempt * 100_000_000))
                continue
            }
            throw error
        }
    }
    
    throw lastError!
}
```

## Best Practices

### Keep Transactions Short

```swift
// Good: Quick transaction
try await db.withTransaction { db in
    try await Order.insert { ... }.execute(db)
    try await OrderItem.insert { ... }.execute(db)
}

// Bad: Long-running transaction
try await db.withTransaction { db in
    let users = try await User.fetchAll(db)
    for user in users {
        // Avoid complex processing in transactions
        let result = await processUserData(user) // Bad!
        try await updateUser(user, result, db)
    }
}
```

### Use Appropriate Isolation

- **Default (Read Committed)**: Most operations
- **Repeatable Read**: Reports, analytics
- **Serializable**: Financial transactions, critical updates

### Handle Failures Gracefully

```swift
do {
    try await db.withTransaction { db in
        try await performOperations(db)
    }
} catch {
    // Log the error
    logger.error("Transaction failed: \(error)")
    
    // Decide how to handle it
    if isRetryable(error) {
        // Retry logic
    } else {
        // User-facing error
        throw UserError.operationFailed
    }
}
```

## Complete Example

```swift
struct OrderService {
    @Dependency(\.defaultDatabase) var db
    
    func placeOrder(
        userId: Int,
        items: [(productId: Int, quantity: Int)]
    ) async throws -> Order {
        try await db.withTransaction(isolation: .serializable) { db in
            // Create order
            let order = try await Order.insert {
                Order.Draft(
                    userId: userId,
                    status: "pending",
                    createdAt: Date()
                )
            }
            .returning(\.self)
            .fetchOne(db)!
            
            var totalAmount: Decimal = 0
            
            // Process each item
            for item in items {
                // Get product and check stock
                let product = try await Product
                    .filter { $0.id == item.productId }
                    .fetchOne(db)
                
                guard let product else {
                    throw OrderError.productNotFound(item.productId)
                }
                
                guard product.stock >= item.quantity else {
                    throw OrderError.insufficientStock(product.name)
                }
                
                // Update stock
                try await Product
                    .filter { $0.id == item.productId }
                    .update { $0.stock -= item.quantity }
                    .execute(db)
                
                // Create order item
                try await OrderItem.insert {
                    OrderItem.Draft(
                        orderId: order.id,
                        productId: item.productId,
                        quantity: item.quantity,
                        price: product.price
                    )
                }.execute(db)
                
                totalAmount += product.price * Decimal(item.quantity)
            }
            
            // Update order with total
            try await Order
                .filter { $0.id == order.id }
                .update { 
                    $0.totalAmount = totalAmount
                    $0.status = "confirmed"
                }
                .execute(db)
            
            return order
        }
    }
}
```

## Next Steps

- Learn about <doc:HandlingMigrations> to manage schema changes
- Explore <doc:TestingWithRecords> for testing transactional code