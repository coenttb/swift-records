# Getting Started

Learn how to set up Swift Records and perform basic database operations.

## Setup

Swift Records requires a PostgreSQL database and uses environment variables for configuration.

### Environment Variables

Set these environment variables for your database connection:

```bash
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=myapp
export DATABASE_USER=postgres
export DATABASE_PASSWORD=password
```

### Initial Configuration

Configure the database dependency at your application's entry point:

```swift
import Records
import Dependencies

@main
struct MyApp {
    static func main() async throws {
        // Configure database
        let db = try await Database.Pool(
            configuration: .fromEnvironment(),
            minConnections: 5,
            maxConnections: 20
        )
        
        prepareDependencies {
            $0.defaultDatabase = db
        }
        
        // Run your app
        await runApp()
    }
}
```

## Queue vs Pool

Choose the right connection strategy for your needs:

### Use Queue for:
- Development and testing
- Simple applications
- Single-user scenarios

```swift
let db = try await Database.Queue(
    configuration: .fromEnvironment()
)

prepareDependencies {
    $0.defaultDatabase = db
}
```

### Use Pool for:
- Production applications
- Multi-user scenarios
- High concurrency

```swift
let db = try await Database.Pool(
    configuration: .fromEnvironment(),
    minConnections: 5,
    maxConnections: 20
)

prepareDependencies {
    $0.defaultDatabase = db
}
```

## Basic Operations

### Define Your Model

Use the `@Table` macro from StructuredQueries:

```swift
import StructuredQueriesPostgres

@Table("users")
struct User {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date
}
```

### Fetch Data

```swift
struct UserService {
    @Dependency(\.defaultDatabase) var db
    
    // Fetch all users
    func fetchAllUsers() async throws -> [User] {
        try await db.read { db in
            try await User.fetchAll(db)
        }
    }
    
    // Fetch with filtering
    func fetchUser(email: String) async throws -> User? {
        try await db.read { db in
            try await User
                .filter { $0.email == email }
                .fetchOne(db)
        }
    }
    
    // Fetch with ordering and limit
    func fetchRecentUsers(limit: Int) async throws -> [User] {
        try await db.read { db in
            try await User
                .order(by: .descending(\.createdAt))
                .limit(limit)
                .fetchAll(db)
        }
    }
}
```

### Insert Data

```swift
func createUser(name: String, email: String) async throws -> User {
    try await db.write { db in
        try await User.insert {
            User.Draft(
                name: name,
                email: email,
                createdAt: Date()
            )
        }
        .returning(\.self)
        .fetchOne(db)!
    }
}

// Insert multiple records
func createUsers(_ users: [(name: String, email: String)]) async throws {
    try await db.write { db in
        for user in users {
            try await User.insert {
                User.Draft(
                    name: user.name,
                    email: user.email,
                    createdAt: Date()
                )
            }.execute(db)
        }
    }
}
```

### Update Data

```swift
func updateUserName(id: Int, newName: String) async throws {
    try await db.write { db in
        try await User
            .filter { $0.id == id }
            .update { $0.name = newName }
            .execute(db)
    }
}

// Update multiple fields
func updateUser(id: Int, name: String, email: String) async throws {
    try await db.write { db in
        try await User
            .filter { $0.id == id }
            .update { user in
                user.name = name
                user.email = email
            }
            .execute(db)
    }
}
```

### Delete Data

```swift
func deleteUser(id: Int) async throws {
    try await db.write { db in
        try await User
            .filter { $0.id == id }
            .delete()
            .execute(db)
    }
}

// Delete with conditions
func deleteInactiveUsers(before date: Date) async throws {
    try await db.write { db in
        try await User
            .filter { $0.createdAt < date }
            .delete()
            .execute(db)
    }
}
```

## Complete Example

Here's a complete example putting it all together:

```swift
import Records
import StructuredQueriesPostgres
import Dependencies

@Table("todos")
struct Todo {
    let id: Int
    let title: String
    let completed: Bool
    let userId: Int
}

struct TodoService {
    @Dependency(\.defaultDatabase) var db
    
    func createTodo(title: String, userId: Int) async throws -> Todo {
        try await db.write { db in
            try await Todo.insert {
                Todo.Draft(
                    title: title,
                    completed: false,
                    userId: userId
                )
            }
            .returning(\.self)
            .fetchOne(db)!
        }
    }
    
    func getUserTodos(userId: Int) async throws -> [Todo] {
        try await db.read { db in
            try await Todo
                .filter { $0.userId == userId }
                .order(by: .ascending(\.id))
                .fetchAll(db)
        }
    }
    
    func toggleTodo(id: Int) async throws {
        try await db.write { db in
            // First fetch the current state
            let todo = try await Todo
                .filter { $0.id == id }
                .fetchOne(db)
            
            guard let todo else { return }
            
            // Toggle the completed state
            try await Todo
                .filter { $0.id == id }
                .update { $0.completed = !todo.completed }
                .execute(db)
        }
    }
    
    func deleteCompletedTodos(userId: Int) async throws {
        try await db.write { db in
            try await Todo
                .filter { $0.userId == userId && $0.completed == true }
                .delete()
                .execute(db)
        }
    }
}
```

## Next Steps

- Learn about <doc:WorkingWithTransactions> for atomic operations
- Set up <doc:HandlingMigrations> to manage your schema
- Explore <doc:TestingWithRecords> for writing database tests
