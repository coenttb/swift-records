# Handling Migrations

Learn how to manage database schema changes using Swift Records migrations.

## What Are Migrations?

Migrations are versioned changes to your database schema. They allow you to:
- Track schema changes over time
- Apply changes consistently across environments
- Collaborate with team members on database changes

## Setting Up Migrations

Create a migrator and register your migrations:

```swift
import Records

extension Database.Migrator {
    static func appMigrations() -> Database.Migrator {
        var migrator = Database.Migrator()
        
        // Register migrations in order
        migrator.registerMigration("001_create_users") { db in
            try await db.execute("""
                CREATE TABLE users (
                    id SERIAL PRIMARY KEY,
                    email TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        }
        
        migrator.registerMigration("002_create_posts") { db in
            try await db.execute("""
                CREATE TABLE posts (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id),
                    title TEXT NOT NULL,
                    content TEXT,
                    published_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        }
        
        migrator.registerMigration("003_add_user_indexes") { db in
            try await db.execute("""
                CREATE INDEX idx_users_email ON users(email);
                CREATE INDEX idx_posts_user_id ON posts(user_id);
            """)
        }
        
        return migrator
    }
}
```

## Running Migrations

Apply migrations at application startup:

```swift
@main
struct MyApp {
    static func main() async throws {
        // Configure database
        let db = try await Database.Pool(
            configuration: .fromEnvironment()
        )
        
        prepareDependencies {
            $0.defaultDatabase = db
        }
        
        // Run migrations
        let migrator = Database.Migrator.appMigrations()
        try await migrator.migrate(db)
        
        // Start your app
        await runApp()
    }
}
```

## Migration Examples

### Creating Tables

```swift
migrator.registerMigration("create_products") { db in
    try await db.execute("""
        CREATE TABLE products (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name TEXT NOT NULL,
            description TEXT,
            price DECIMAL(10,2) NOT NULL,
            stock INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
}
```

### Adding Columns

```swift
migrator.registerMigration("add_user_fields") { db in
    try await db.execute("""
        ALTER TABLE users
        ADD COLUMN phone TEXT,
        ADD COLUMN verified BOOLEAN DEFAULT FALSE,
        ADD COLUMN last_login TIMESTAMP
    """)
}
```

### Creating Indexes

```swift
migrator.registerMigration("optimize_queries") { db in
    try await db.execute("""
        -- Regular index
        CREATE INDEX idx_products_name ON products(name);
        
        -- Unique index
        CREATE UNIQUE INDEX idx_users_phone ON users(phone) 
        WHERE phone IS NOT NULL;
        
        -- Composite index
        CREATE INDEX idx_posts_user_published 
        ON posts(user_id, published_at DESC);
    """)
}
```

### Data Migrations

Combine schema changes with data updates:

```swift
migrator.registerMigration("normalize_emails") { db in
    // Add new column
    try await db.execute("""
        ALTER TABLE users
        ADD COLUMN email_normalized TEXT
    """)
    
    // Update existing data
    let users = try await User.fetchAll(db)
    for user in users {
        let normalized = user.email.lowercased()
        try await User
            .filter { $0.id == user.id }
            .update { $0.emailNormalized = normalized }
            .execute(db)
    }
    
    // Make it required and unique
    try await db.execute("""
        ALTER TABLE users
        ALTER COLUMN email_normalized SET NOT NULL;
        
        CREATE UNIQUE INDEX idx_users_email_normalized 
        ON users(email_normalized);
    """)
}
```

## Migration Organization

### Naming Convention

Use a consistent naming pattern:

```swift
// Format: XXX_description
"001_create_users"
"002_add_user_verification"
"003_create_posts"
"004_add_post_comments"
```

### Separate by Feature

Organize complex migrations:

```swift
extension Database.Migrator {
    static func userMigrations() -> Database.Migrator {
        var migrator = Database.Migrator()
        migrator.registerMigration("001_create_users") { ... }
        migrator.registerMigration("002_add_user_profiles") { ... }
        return migrator
    }
    
    static func blogMigrations() -> Database.Migrator {
        var migrator = Database.Migrator()
        migrator.registerMigration("010_create_posts") { ... }
        migrator.registerMigration("011_add_comments") { ... }
        return migrator
    }
    
    static func appMigrations() -> Database.Migrator {
        var migrator = Database.Migrator()
        
        // Combine all migrations
        let userMigrator = userMigrations()
        let blogMigrator = blogMigrations()
        
        // Register in order
        // ... combine migrations ...
        
        return migrator
    }
}
```

## Development Workflow

### Reset During Development

For development, you can reset the database on schema changes:

```swift
#if DEBUG
var migrator = Database.Migrator.appMigrations()
migrator.eraseDatabaseOnSchemaChange = true
try await migrator.migrate(db)
#else
let migrator = Database.Migrator.appMigrations()
try await migrator.migrate(db)
#endif
```

⚠️ **Warning**: Never use `eraseDatabaseOnSchemaChange` in production!

### Check Migration Status

```swift
let migrator = Database.Migrator.appMigrations()

// Check if all migrations are applied
let isUpToDate = try await migrator.hasCompletedMigrations(db)

if !isUpToDate {
    print("Database needs migration")
    try await migrator.migrate(db)
}

// Get list of applied migrations
let applied = try await db.read { db in
    try await migrator.appliedIdentifiers(db)
}
print("Applied migrations: \(applied)")
```

## Best Practices

### Make Migrations Idempotent

Use `IF NOT EXISTS` and `IF EXISTS`:

```swift
migrator.registerMigration("create_tables") { db in
    try await db.execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_categories_name 
        ON categories(name);
    """)
}
```

### Keep Migrations Small

Break large changes into smaller steps:

```swift
// Good: Separate migrations
migrator.registerMigration("add_column") { db in
    try await db.execute("""
        ALTER TABLE users ADD COLUMN status TEXT
    """)
}

migrator.registerMigration("populate_status") { db in
    try await db.execute("""
        UPDATE users SET status = 'active' WHERE status IS NULL
    """)
}

migrator.registerMigration("make_status_required") { db in
    try await db.execute("""
        ALTER TABLE users ALTER COLUMN status SET NOT NULL
    """)
}
```

### Handle Foreign Keys

Use deferred foreign key checks when needed:

```swift
var migrator = Database.Migrator()
migrator.foreignKeyChecks = .deferred

migrator.registerMigration("restructure_tables") { db in
    // Complex migration with circular references
    // Foreign keys checked at transaction end
}
```

## Complete Example

```swift
import Records
import StructuredQueriesPostgres

// Models
@Table("users")
struct User {
    let id: Int
    let email: String
    let name: String
}

@Table("todos")
struct Todo {
    let id: Int
    let userId: Int
    let title: String
    let completed: Bool
}

// Migrations
extension Database.Migrator {
    static func todoAppMigrations() -> Database.Migrator {
        var migrator = Database.Migrator()
        
        // Initial schema
        migrator.registerMigration("001_create_users") { db in
            try await db.execute("""
                CREATE TABLE users (
                    id SERIAL PRIMARY KEY,
                    email TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        }
        
        migrator.registerMigration("002_create_todos") { db in
            try await db.execute("""
                CREATE TABLE todos (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    completed BOOLEAN DEFAULT FALSE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        }
        
        // Add indexes for performance
        migrator.registerMigration("003_add_indexes") { db in
            try await db.execute("""
                CREATE INDEX idx_todos_user_id ON todos(user_id);
                CREATE INDEX idx_todos_completed ON todos(completed);
            """)
        }
        
        // Add new feature
        migrator.registerMigration("004_add_todo_priority") { db in
            try await db.execute("""
                ALTER TABLE todos 
                ADD COLUMN priority INTEGER DEFAULT 0;
                
                CREATE INDEX idx_todos_priority 
                ON todos(user_id, priority DESC);
            """)
        }
        
        return migrator
    }
}

// App startup
@main
struct TodoApp {
    static func main() async throws {
        // Setup database
        let db = try await Database.Pool(
            configuration: .fromEnvironment()
        )
        
        prepareDependencies {
            $0.defaultDatabase = db
        }
        
        // Run migrations
        let migrator = Database.Migrator.todoAppMigrations()
        
        do {
            try await migrator.migrate(db)
            print("✅ Migrations completed successfully")
        } catch {
            print("❌ Migration failed: \(error)")
            throw error
        }
        
        // Start app
        await runApp()
    }
}
```

## Next Steps

- Learn about <doc:TestingWithRecords> to test your migrations
- Review <doc:WorkingWithTransactions> for complex migration operations
