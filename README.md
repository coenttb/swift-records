# Swift Records

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-blue.svg)
![Apache 2.0 License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)

A high-level, type-safe database abstraction layer for PostgreSQL in Swift, built on [StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) and [PostgresNIO](https://github.com/vapor/postgres-nio), inspired by GRDB.

## Features

- 🏊 **Connection Pooling**: Automatic connection lifecycle management with configurable pool sizes
- 🔄 **Transactions**: Full transaction support with isolation levels and savepoints
- 📦 **Migrations**: Version-tracked schema migrations with automatic execution
- 🧪 **Testing Utilities**: Schema isolation for parallel test execution
- 🎯 **Type Safety**: Leverages Swift's type system and StructuredQueries for compile-time guarantees
- 🚀 **Actor-Based Concurrency**: Safe multi-threaded database access with Swift 6.0 concurrency
- 🔌 **Dependency Injection**: Seamless integration with Point-Free's Dependencies library

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/coenttb/swift-records", from: "0.0.1")
]

targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "Records", package: "swift-records")
        ]
    ),
    .testTarget(
        name: "YourTargetTests",
        dependencies: [
            .product(name: "RecordsTestSupport", package: "swift-records")
        ]
    )
]
```

**Requirements:**
- Swift 6.0+
- PostgreSQL 12+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+

## Quick Start

### Basic Setup

```swift
import Records
import StructuredQueries

// Define your model using @Table macro
@Table("users")
struct User {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date
}

// Configure database at app startup
import Dependencies

@main
struct MyApp {
    static func main() async throws {
        // Configure with explicit settings
        try await prepareDependencies {
            $0.defaultDatabase = try await Database.Pool(
                configuration: .init(
                    host: "localhost",
                    port: 5432,
                    database: "myapp",
                    username: "postgres",
                    password: "password"
                ),
                minConnections: 5,
                maxConnections: 20
            )
        }
        
        // Or use environment variables
        try await prepareDependencies {
            $0.defaultDatabase = try await Database.Pool(
                configuration: .fromEnvironment(),
                minConnections: 5,
                maxConnections: 20
            )
        }
        
        // Your app code here...
    }
}
```

### Query Operations

```swift
import Dependencies

// Access database via dependency injection
struct UserService {
    @Dependency(\.defaultDatabase) var db
    
    // Fetch all users
    func fetchUsers() async throws -> [User] {
        try await db.read { db in
            try await User.fetchAll(db)
        }
    }
    
    // Fetch with conditions
    func fetchActiveUsers() async throws -> [User] {
        try await db.read { db in
            try await User
                .filter { $0.isActive }
                .order(by: .descending(\.createdAt))
                .limit(10)
                .fetchAll(db)
        }
    }
    
    // Insert new user
    func createUser(name: String, email: String) async throws {
        try await db.write { db in
            try await User.insert {
                ($0.name, $0.email, $0.createdAt)
            } values: {
                (name, email, Date())
            }.execute(db)
        }
    }
    
    // Update user
    func updateUserName(email: String, newName: String) async throws {
        try await db.write { db in
            try await User
                .filter { $0.email == email }
                .update { $0.name = newName }
                .execute(db)
        }
    }
    
    // Delete old users
    func deleteOldUsers(olderThan date: Date) async throws {
        try await db.write { db in
            try await User
                .filter { $0.createdAt < date }
                .delete()
                .execute(db)
        }
    }
}
```

### Transactions

```swift
struct TransferService {
    @Dependency(\.defaultDatabase) var db
    
    // Basic transaction
    func createUserWithProfile(name: String, email: String) async throws {
        try await db.withTransaction { db in
            let userId = try await User.insert {
                ($0.name, $0.email, $0.createdAt)
            } values: {
                (name, email, Date())
            }
            .returning(\.id)
            .fetchOne(db)
            
            try await Profile.insert {
                ($0.userId, $0.bio)
            } values: {
                (userId!, "New user")
            }.execute(db)
            // Both succeed or both are rolled back
        }
    }
    
    // Transaction with isolation level
    func transferFunds(from: Int, to: Int, amount: Decimal) async throws {
        try await db.withTransaction(isolation: .serializable) { db in
            // Your transactional operations
        }
    }
}

// Savepoints for nested transactions
try await db.withTransaction { db in
    try await User.insert { ... }.execute(db)
    
    do {
        try await db.withSavepoint("risky_operation") { db in
            try await riskyOperation(db)
        }
    } catch {
        // Only the savepoint is rolled back
        print("Risky operation failed: \\(error)")
    }
    
    try await Post.insert { ... }.execute(db)
}
```

### Migrations

```swift
// Define migrations
struct CreateUsersTable {
    func apply(_ db: any Database.Connection.`Protocol`) async throws {
        try await db.execute("""
            CREATE TABLE users (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                "createdAt" TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )
        """)
    }
}

// Apply migrations at app startup
@main
struct MyApp {
    static func main() async throws {
        // Configure database
        try await prepareDependencies {
            $0.defaultDatabase = try await Database.Pool(
                configuration: .fromEnvironment()
            )
        }
        
        // Run migrations
        @Dependency(\.defaultDatabase) var db
        
        var migrator = Database.Migrator()
        migrator.registerMigration("create_users_table") { db in
            try await CreateUsersTable().apply(db)
        }
        
        try await migrator.migrate(db)
        
        // Start your app...
    }
}
```

## Testing

The `RecordsTestSupport` module provides utilities for testing with automatic schema isolation:

```swift
import Testing
import Records
import RecordsTestSupport
import Dependencies

@Suite("User Tests", .dependency(\.database, Database.TestDatabase.withSchema()))
struct UserTests {
    @Dependency(\\.database) var db
    
    @Test func createUser() async throws {
        // Each test runs in its own schema, enabling parallel execution
        try await db.withRollback { db in
            let user = try await User.insert {
                ($0.name, $0.email)
            } values: {
                ("Test User", "test@example.com")
            }
            .returning(\\.self)
            .execute(db)
            
            #expect(user.first?.name == "Test User")
        }
    }
}
```

### Test Database Configuration

Tests use environment variables for database configuration:

```bash
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=test_db
export DATABASE_USER=postgres
export DATABASE_PASSWORD=password
```

Or create a `.env` file in your test directory:

```env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=test_db
DATABASE_USER=postgres
DATABASE_PASSWORD=password
```

## Architecture

Swift Records provides a layered architecture:

1. **Database Layer**: Top-level coordinator with `Reader` and `Writer` actors
2. **Connection Management**: Automatic pooling with configurable min/max connections
3. **Query Execution**: Type-safe query building via StructuredQueries
4. **PostgreSQL Bridge**: Low-level utilities from swift-structured-queries-postgres

### Connection Pooling

The connection pool automatically manages connection lifecycle:

- Maintains minimum connections for quick response
- Scales up to maximum under load
- Validates connections before reuse
- Handles connection failures gracefully

### Concurrency Safety

Using Swift 6.0's actor model ensures thread-safe database access:

- `Database.Reader`: Read-only operations (can use multiple connections)
- `Database.Writer`: Write operations (ensures serialization when needed)

## Advanced Usage

### Custom Query Types

```swift
@Selection
struct UserWithPosts {
    let userId: Int
    let userName: String
    let postCount: Int
}

let results = try await db.reader.read { db in
    try await User
        .join(Post.all) { $0.id.eq($1.userId) }
        .group(by: { user, _ in user.id })
        .select { user, post in
            UserWithPosts.Columns(
                userId: user.id,
                userName: user.name,
                postCount: post.id.count()
            )
        }
        .fetchAll(db)
}
```

### Raw SQL

When needed, you can execute raw SQL:

```swift
struct MaintenanceService {
    @Dependency(\.defaultDatabase) var db
    
    func createEmailIndex() async throws {
        try await db.write { db in
            try await db.execute("""
                CREATE INDEX CONCURRENTLY idx_users_email 
                ON users(email)
            """)
        }
    }
    
    func vacuumDatabase() async throws {
        try await db.write { db in
            try await db.execute("VACUUM ANALYZE")
        }
    }
}
```

## Dependencies

This package builds on excellent work from:
- [StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) - Type-safe SQL generation
- [PostgresNIO](https://github.com/vapor/postgres-nio) - PostgreSQL driver
- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) - Dependency injection

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [Point-Free](https://www.pointfree.co) for StructuredQueries and Dependencies
- The [Vapor](https://vapor.codes) team for PostgresNIO
- The Swift community for continuous inspiration
