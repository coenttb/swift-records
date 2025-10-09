import Dependencies
import Foundation
@testable import Records
import ResourcePool
import struct ResourcePool.Statistics
import struct ResourcePool.Metrics
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

    /// Creates the Reminder test schema (matches upstream swift-structured-queries)
    func createReminderSchema() async throws {
        try await self.write { db in
            // Create remindersLists table
            try await db.execute("""
                CREATE TABLE "remindersLists" (
                    "id" SERIAL PRIMARY KEY,
                    "color" INTEGER NOT NULL DEFAULT 4889071,
                    "title" TEXT NOT NULL DEFAULT '',
                    "position" INTEGER NOT NULL DEFAULT 0
                )
            """)

            // Create unique index on title
            try await db.execute("""
                CREATE UNIQUE INDEX "remindersLists_title" ON "remindersLists"("title")
            """)

            // Create reminders table
            try await db.execute("""
                CREATE TABLE "reminders" (
                    "id" SERIAL PRIMARY KEY,
                    "assignedUserID" INTEGER,
                    "dueDate" DATE,
                    "isCompleted" BOOLEAN NOT NULL DEFAULT false,
                    "isFlagged" BOOLEAN NOT NULL DEFAULT false,
                    "notes" TEXT NOT NULL DEFAULT '',
                    "priority" INTEGER,
                    "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
                    "title" TEXT NOT NULL DEFAULT '',
                    "updatedAt" TIMESTAMP NOT NULL DEFAULT '2040-02-14 23:31:30'
                )
            """)

            // Create users table (simple version for reminders)
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS "users" (
                    "id" SERIAL PRIMARY KEY,
                    "name" TEXT NOT NULL DEFAULT ''
                )
            """)

            // Create index on remindersListID
            try await db.execute("""
                CREATE INDEX "index_reminders_on_remindersListID"
                ON "reminders"("remindersListID")
            """)

            // Create tags table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS "tags" (
                    "id" SERIAL PRIMARY KEY,
                    "title" TEXT NOT NULL UNIQUE
                )
            """)

            // Create remindersTags junction table
            try await db.execute("""
                CREATE TABLE "remindersTags" (
                    "reminderID" INTEGER NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                    "tagID" INTEGER NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE,
                    PRIMARY KEY ("reminderID", "tagID")
                )
            """)
        }
    }

    /// Inserts Reminder sample data (matches upstream test data)
    package func insertReminderSampleData() async throws {
        try await self.write { db in
            // Insert reminders lists
            try await db.execute("""
                INSERT INTO "remindersLists" ("id", "color", "title", "position") VALUES
                (1, 4889071, 'Home', 0),
                (2, 16744448, 'Work', 1)
            """)

            // Insert users
            try await db.execute("""
                INSERT INTO "users" ("id", "name") VALUES
                (1, 'Alice'),
                (2, 'Bob')
            """)

            // Insert reminders
            try await db.execute("""
                INSERT INTO "reminders"
                ("id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
                VALUES
                (1, 1, '2001-01-01', false, false, 'Milk, Eggs, Apples', NULL, 1, 'Groceries', '2040-02-14 23:31:30'),
                (2, NULL, '2000-12-30', false, true, '', NULL, 1, 'Haircut', '2040-02-14 23:31:30'),
                (3, NULL, '2001-01-01', false, false, 'Ask about diet', 2, 1, 'Vet appointment', '2040-02-14 23:31:30'),
                (4, 2, '2001-01-02', true, false, '', 1, 2, 'Finish report', '2040-02-14 23:31:30'),
                (5, NULL, '2001-01-03', false, true, 'Prepare slides', 1, 2, 'Team meeting', '2040-02-14 23:31:30'),
                (6, 1, '2001-01-04', false, false, '', 2, 2, 'Review PR', '2040-02-14 23:31:30')
            """)

            // Insert tags
            try await db.execute("""
                INSERT INTO "tags" ("id", "title") VALUES
                (1, 'car'),
                (2, 'kids'),
                (3, 'someday'),
                (4, 'optional')
            """)

            // Insert reminder-tag relationships
            try await db.execute("""
                INSERT INTO "remindersTags" ("reminderID", "tagID") VALUES
                (1, 1),
                (1, 2),
                (2, 1),
                (3, 4)
            """)

            // Reset sequences to correct values after explicit inserts
            // Note: PostgreSQL creates sequences with quoted table names as "tableName_columnName_seq"
            try await db.execute("""
                SELECT setval(pg_get_serial_sequence('"remindersLists"', 'id'), (SELECT MAX(id) FROM "remindersLists"))
            """)

            try await db.execute("""
                SELECT setval(pg_get_serial_sequence('"reminders"', 'id'), (SELECT MAX(id) FROM "reminders"))
            """)

            try await db.execute("""
                SELECT setval(pg_get_serial_sequence('"users"', 'id'), (SELECT MAX(id) FROM "users"))
            """)

            try await db.execute("""
                SELECT setval(pg_get_serial_sequence('"tags"', 'id'), (SELECT MAX(id) FROM "tags"))
            """)
        }
    }
}

// MARK: - Test Database Factory for Dependencies

/// A wrapper that provides test databases via ResourcePool
///
/// This replaces the previous DatabaseManager approach with ResourcePool for:
/// - Better thundering herd prevention (direct handoff vs broadcast)
/// - FIFO fairness guarantees (tests served in arrival order)
/// - Comprehensive metrics (wait times, handoff rates, utilization)
/// - Sophisticated pre-warming (synchronous first resource + background remainder)
/// - Resource validation and cycling capabilities
///
/// Each test suite gets its own isolated database pool for data isolation.
/// Connection limits are managed per-database to prevent PostgreSQL exhaustion.
public final class LazyTestDatabase: Database.Writer, @unchecked Sendable {
    private let pool: ResourcePool<Database.TestDatabase>

    public enum SetupMode: Sendable {
        case empty
        case withSchema
        case withSampleData
        case withReminderSchema
        case withReminderData

        var databaseSetupMode: Database.TestDatabaseSetupMode {
            switch self {
            case .empty: return .empty
            case .withSchema: return .withSchema
            case .withSampleData: return .withSampleData
            case .withReminderSchema: return .withReminderSchema
            case .withReminderData: return .withReminderData
            }
        }
    }

    /// Initialize a test database pool
    ///
    /// - Parameters:
    ///   - setupMode: Schema and data setup mode
    ///   - capacity: Maximum number of databases in pool (default 1 for suite-level usage)
    ///   - warmup: Whether to pre-create resources (default true)
    ///   - timeout: Default timeout for resource acquisition (default 30s)
    ///   - minConnections: Minimum connections per database (nil = single connection)
    ///   - maxConnections: Maximum connections per database (nil = single connection)
    public init(
        setupMode: SetupMode,
        capacity: Int = 1,
        warmup: Bool = true,
        timeout: Duration = .seconds(30),
        minConnections: Int? = nil,
        maxConnections: Int? = nil
    ) async throws {
        self.pool = try await ResourcePool(
            capacity: capacity,
            resourceConfig: Database.TestDatabase.Config(
                setupMode: setupMode.databaseSetupMode,
                configuration: nil,
                prefix: "test",
                minConnections: minConnections,
                maxConnections: maxConnections
            ),
            warmup: warmup
        )
    }

    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await pool.withResource(timeout: .seconds(30)) { database in
            try await database.read(block)
        }
    }

    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await pool.withResource(timeout: .seconds(30)) { database in
            try await database.write(block)
        }
    }

    public func close() async throws {
        try await pool.drain(timeout: .seconds(30))
        await pool.close()
    }

    /// Get pool statistics for debugging
    public var statistics: Statistics {
        get async {
            await pool.statistics
        }
    }

    /// Get pool metrics for observability
    public var metrics: Metrics {
        get async {
            await pool.metrics
        }
    }
}

// MARK: - Convenience Factory Methods

extension Database.TestDatabase {
    /// Creates a test database with User/Post schema
    ///
    /// Uses ResourcePool with capacity=1 (suite-level single database).
    /// For parallel test execution within a suite, increase capacity.
    public static func withSchema() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withSchema,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with User/Post schema and sample data
    ///
    /// Uses ResourcePool with capacity=1 (suite-level single database).
    /// For parallel test execution within a suite, increase capacity.
    public static func withSampleData() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withSampleData,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with Reminder schema (matches upstream)
    ///
    /// Uses ResourcePool with capacity=1 (suite-level single database).
    /// For parallel test execution within a suite, increase capacity.
    public static func withReminderSchema() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withReminderSchema,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with Reminder schema and sample data (matches upstream)
    ///
    /// Uses ResourcePool with capacity=1 (suite-level single database).
    /// For parallel test execution within a suite, increase capacity.
    public static func withReminderData() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a pooled test database for parallel test execution
    ///
    /// Use this for test suites with many parallel tests.
    ///
    /// - Parameters:
    ///   - setupMode: Schema and data setup mode
    ///   - capacity: Number of databases in pool (recommended: 3-5 for parallel tests)
    public static func withPooled(
        setupMode: LazyTestDatabase.SetupMode,
        capacity: Int = 5
    ) async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: setupMode,
            capacity: capacity,
            warmup: true
        )
    }

    /// Creates a test database with connection pool for concurrency stress testing
    ///
    /// Unlike `withReminderData()` which uses a single connection, this creates
    /// a database with a proper connection pool that can handle many concurrent requests.
    ///
    /// **Use this for concurrency stress tests** that spawn 100+ parallel operations.
    ///
    /// ## Architecture
    ///
    /// - Creates ONE test schema (one isolated database)
    /// - Uses `testDatabasePool()` with multiple connections (not `testDatabase()`)
    /// - All concurrent requests queue and wait for available connections
    /// - Proper connection pooling behavior under load
    /// - Each test suite gets isolated database to prevent data pollution
    ///
    /// ## Example
    ///
    /// ```swift
    /// @Suite(
    ///     "Concurrency Tests",
    ///     .dependencies {
    ///         $0.envVars = .development
    ///         $0.defaultDatabase = try await Database.TestDatabase.withConnectionPool(
    ///             setupMode: .withReminderData,
    ///             minConnections: 5,
    ///             maxConnections: 20
    ///         )
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - setupMode: Schema and data setup mode
    ///   - minConnections: Minimum connections in pool (default: 2, aggressively reduced for cmd+U)
    ///   - maxConnections: Maximum connections in pool (default: 10, aggressively reduced for cmd+U)
    /// - Returns: A lazy test database with connection pooling enabled
    public static func withConnectionPool(
        setupMode: LazyTestDatabase.SetupMode,
        minConnections: Int = 2,
        maxConnections: Int = 10
    ) async throws -> LazyTestDatabase {
        // Use LazyTestDatabase with connection pool config
        // Aggressively reduced connection limits to prevent PostgreSQL exhaustion when running all test suites
        // With 13 test suites × 10 max connections = 130 connections (well within PostgreSQL's 400 default limit)
        try await LazyTestDatabase(
            setupMode: setupMode,
            capacity: 1,  // Only need 1 database (it has connection pool internally)
            warmup: true,
            minConnections: minConnections,
            maxConnections: maxConnections
        )
    }
}
