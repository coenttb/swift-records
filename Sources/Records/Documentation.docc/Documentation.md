# ``Records``

High-level database abstraction layer for PostgreSQL in Swift.

## Overview

Swift Records provides a type-safe, high-level interface for PostgreSQL databases with connection pooling, transactions, and migrations. Built on [StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) and [PostgresNIO](https://github.com/vapor/postgres-nio).

### Quick Start

```swift
import Records
import Dependencies

// 1. Configure database at app startup
let db = try await Database.Pool(
    configuration: .fromEnvironment(),
    minConnections: 5,
    maxConnections: 20
)

prepareDependencies {
    $0.defaultDatabase = db
}

// 2. Use in your code
struct UserService {
    @Dependency(\.defaultDatabase) var db
    
    func fetchUsers() async throws -> [User] {
        try await db.read { db in
            try await User.fetchAll(db)
        }
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:WorkingWithTransactions>
- <doc:HandlingMigrations>
- <doc:TestingWithRecords>

### Core Types

- ``Database``
- ``Database/Queue``
- ``Database/Pool``
- ``Database/Configuration``
- ``Database/Migrator``

### Database Operations

- ``Database/Reader``
- ``Database/Writer``
- ``Database/Connection/Protocol``

### Transactions

- ``TransactionIsolationLevel``

### Testing

- ``TestDatabase``
- ``TestDatabasePool``