import Dependencies
import Foundation
@testable import Records
import StructuredQueriesPostgres
import Testing

// MARK: - Test Database Setup

extension Database.Writer {
    /// Creates the standard test schema for testing
    func createTestSchema() async throws {
        try await self.write { db in
            // Create users table
            try await db.execute("""
                CREATE TABLE users (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE NOT NULL,
                    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Create posts table
            try await db.execute("""
                CREATE TABLE posts (
                    id SERIAL PRIMARY KEY,
                    "userId" INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    "publishedAt" TIMESTAMP
                )
            """)

            // Create comments table
            try await db.execute("""
                CREATE TABLE comments (
                    id SERIAL PRIMARY KEY,
                    "postId" INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
                    "userId" INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,
                    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Create tags table
            try await db.execute("""
                CREATE TABLE tags (
                    id SERIAL PRIMARY KEY,
                    name TEXT UNIQUE NOT NULL
                )
            """)

            // Create post_tags junction table
            try await db.execute("""
                CREATE TABLE post_tags (
                    "postId" INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
                    "tagId" INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY ("postId", "tagId")
                )
            """)
        }
    }

    /// Inserts sample data for testing
    package func insertSampleData() async throws {
        try await self.write { db in
            // Insert users
            try await db.execute("""
                INSERT INTO users (name, email, "createdAt") VALUES
                ('Alice', 'alice@example.com', CURRENT_TIMESTAMP),
                ('Bob', 'bob@example.com', CURRENT_TIMESTAMP)
            """)

            // Insert posts
            try await db.execute("""
                INSERT INTO posts ("userId", title, content, "publishedAt") VALUES
                (1, 'First Post', 'Hello World', CURRENT_TIMESTAMP),
                (2, 'Second Post', 'Another post', NULL)
            """)

            // Insert comments
            try await db.execute("""
                INSERT INTO comments ("postId", "userId", text, "createdAt") VALUES
                (1, 2, 'Great post!', CURRENT_TIMESTAMP)
            """)

            // Insert tags
            try await db.execute("""
                INSERT INTO tags (name) VALUES
                ('Swift'),
                ('Database')
            """)

            // Insert post-tag relationships
            try await db.execute("""
                INSERT INTO post_tags ("postId", "tagId") VALUES
                (1, 1),
                (1, 2)
            """)
        }
    }
}

// MARK: - Test Database Factory for Dependencies

/// Actor to manage database creation using the pool
private actor DatabaseManager {
    private var database: Database.TestDatabase?
    private let setupMode: Database.TestDatabaseSetupMode

    init(setupMode: Database.TestDatabaseSetupMode) {
        self.setupMode = setupMode
    }

    func getDatabase() async throws -> Database.TestDatabase {
        if let database = database {
            return database
        }

        // Acquire from pool
        let mode = setupMode // Capture locally to avoid race
        let newDatabase = try await Database.TestDatabasePool.shared.acquire(setupMode: mode)
        self.database = newDatabase
        return newDatabase
    }

    func cleanup() async {
        if let database = database {
            // Release back to pool
            await Database.TestDatabasePool.shared.release(database)
            self.database = nil
        }
    }
}

/// A wrapper that defers async database creation until first use
public final class LazyTestDatabase: Database.Writer, @unchecked Sendable {
    private let manager: DatabaseManager

    enum SetupMode {
        case empty
        case withSchema
        case withSampleData

        var databaseSetupMode: Database.TestDatabaseSetupMode {
            switch self {
            case .empty: return .empty
            case .withSchema: return .withSchema
            case .withSampleData: return .withSampleData
            }
        }
    }

    init(setupMode: SetupMode) {
        self.manager = DatabaseManager(setupMode: setupMode.databaseSetupMode)
    }

    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let database = try await manager.getDatabase()
        return try await database.read(block)
    }

    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let database = try await manager.getDatabase()
        return try await database.write(block)
    }

    public func close() async throws {
//        await manager.cleanup()
    }

    deinit {
        // Schedule cleanup to return database to pool
        // Note: Task.detached is used here intentionally:
        // 1. We can't use async in deinit
        // 2. We explicitly capture only [manager], not self
        // 3. The manager actor owns the database reference and needs to clean it up
        // 4. This is safe because manager is an actor with its own lifecycle
        Task.detached { [manager] in
            await manager.cleanup()
        }
    }
}

extension Database.TestDatabase {
    /// Creates a test database factory that will set up schema on first use (synchronous for dependency injection)
    public static func withSchema() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSchema)
    }

    /// Creates a test database factory that will set up schema and sample data on first use (synchronous for dependency injection)
    public static func withSampleData() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSampleData)
    }
}
