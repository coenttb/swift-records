import Foundation
import PostgresNIO
import StructuredQueriesPostgres

// MARK: - TestDatabasePool

extension Database {
    /// A pool of test databases that manages connections properly for parallel testing
    actor TestDatabasePool {
        private var inUse: Set<TestDatabaseEntry> = []
        private let configuration: PostgresClient.Configuration?
        private var isShuttingDown = false

        /// Shared instance for test suites
        static let shared = TestDatabasePool()

        init(configuration: PostgresClient.Configuration? = nil) {
            self.configuration = configuration

            // Register cleanup on process termination
            atexit {
                Task.detached {
                    await TestDatabasePool.shared.shutdownAll()
                }
            }
        }

        /// Acquire a test database from the pool
        func acquire(setupMode: TestDatabaseSetupMode = .withSchema) async throws -> TestDatabase {
            guard !isShuttingDown else {
                throw Database.Error.poolShuttingDown
            }

            // Always create a new database with a unique schema for proper isolation
            // This ensures parallel tests never interfere with each other
            let database = try await Database.testDatabase(
                configuration: configuration,
                prefix: "pool"
            )

            let entry = TestDatabaseEntry(database: database)
            inUse.insert(entry)

            switch setupMode {
            case .empty:
                break
            case .withSchema:
                try await database.createTestSchema()
            case .withSampleData:
                try await database.createTestSchema()
                try await database.insertSampleData()
            }

            return database
        }

        /// Release a test database back to the pool
        func release(_ database: TestDatabase) async {
            // Find and remove from in-use set
            let entry = inUse.first { $0.database === database }
            if let entry = entry {
                inUse.remove(entry)
            }

            // Always cleanup immediately since we create fresh databases
            // This ensures connections are closed properly
            await database.cleanup()
        }

        /// Shutdown all databases and close connections
        func shutdownAll() async {
            isShuttingDown = true

            // Close all in-use databases
            for entry in inUse {
                await entry.database.cleanup()
            }
            inUse.removeAll()
        }
    }
}

// MARK: - Supporting Types

extension Database {
    /// Setup mode for test databases
    public enum TestDatabaseSetupMode: Sendable {
        case empty
        case withSchema
        case withSampleData
    }
}

/// Entry for tracking databases in use
private struct TestDatabaseEntry: Hashable {
    let database: Database.TestDatabase
    let id = UUID()

    static func == (lhs: TestDatabaseEntry, rhs: TestDatabaseEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TestDatabase Extensions for Pool

extension Database.TestDatabase {
    /// Clean the schema (drop all tables) without dropping the schema itself
    func cleanSchema() async throws {
        try await write { db in
            // Drop all tables in the current schema
            let dropTablesQuery = """
                DO $$ DECLARE
                    r RECORD;
                BEGIN
                    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = current_schema()) LOOP
                        EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
                    END LOOP;
                END $$;
            """
            try await db.execute(dropTablesQuery)
        }
    }

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
    func insertSampleData() async throws {
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
