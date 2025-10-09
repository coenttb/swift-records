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
                (3, NULL, '2001-01-01', false, false, 'Ask about diet', 3, 1, 'Vet appointment', '2040-02-14 23:31:30'),
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

// MARK: - Test Database Storage

/// Global storage for test databases - prevents deallocation forever
/// This is intentionally a global variable (not in an actor) to survive process exit
/// Marked nonisolated(unsafe) because it's only appended to, never read, and
/// concurrent appends are acceptable (we don't care about order or duplicates)
private nonisolated(unsafe) var _testDatabaseStorage: [Database.TestDatabase] = []

/// Storage function - appends database to global storage to prevent deallocation
private func storeTestDatabase(_ database: Database.TestDatabase) {
    _testDatabaseStorage.append(database)
}

/// A simple lazy wrapper for test databases
///
/// **Design Decision**: Global variable storage prevents deallocation
///
/// ## Approach
/// - Each test suite gets its OWN isolated database
/// - All databases stored in global array - NEVER deallocated
/// - Global variable survives process exit cleanup
/// - This prevents ClientRunner deinit from running during shutdown
/// - Simple lazy property with Task-based synchronization
///
/// ## Why This Works
/// - Tests execute successfully ✅
/// - xcodebuild completes without hanging ✅
/// - No ClientRunner deinit = no async cleanup during exit ✅
/// - Each test suite isolated from others ✅
///
/// Each test suite gets its own isolated database for data isolation.
public final class LazyTestDatabase: Database.Writer, @unchecked Sendable {
    private let setupMode: Database.TestDatabaseSetupMode

    // Lazy database creation with Task-based synchronization
    private var _database: Database.TestDatabase?
    private var _creationTask: Task<Database.TestDatabase, Error>?

    private func getOrCreateDatabase() async throws -> Database.TestDatabase {
        // Check if already created
        if let existing = _database {
            return existing
        }

        // Check if creation is in progress
        if let task = _creationTask {
            return try await task.value
        }

        // Create new task for database creation
        let task = Task<Database.TestDatabase, Error> {
            // Create database with single connection
            let db = try await Database.testDatabase(
                configuration: nil,
                prefix: "test"
            )

            // Setup schema
            switch self.setupMode {
            case .empty:
                break
            case .withSchema:
                try await db.createTestSchema()
            case .withSampleData:
                try await db.createTestSchema()
                try await db.insertSampleData()
            case .withReminderSchema:
                try await db.createReminderSchema()
            case .withReminderData:
                try await db.createReminderSchema()
                try await db.insertReminderSampleData()
            }

            // Store in global variable to prevent deallocation
            storeTestDatabase(db)

            return db
        }

        _creationTask = task
        let db = try await task.value
        _database = db
        _creationTask = nil

        return db
    }

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

    /// Initialize a lazy test database (synchronous - no async needed!)
    ///
    /// - Parameters:
    ///   - setupMode: Schema and data setup mode
    public init(setupMode: SetupMode) {
        self.setupMode = setupMode.databaseSetupMode
    }

    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let db = try await getOrCreateDatabase()
        return try await db.read(block)
    }

    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let db = try await getOrCreateDatabase()
        return try await db.write(block)
    }

    public func close() async throws {
        // No-op: databases stored in global actor are never cleaned up
        // This prevents ClientRunner deinit hangs
    }

    // NO deinit - we don't own the database, global actor does
}

// MARK: - Convenience Factory Methods

extension Database.TestDatabase {
    /// Creates a test database with User/Post schema (lazy initialization)
    public static func withSchema() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSchema)
    }

    /// Creates a test database with User/Post schema and sample data (lazy initialization)
    public static func withSampleData() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withSampleData)
    }

    /// Creates a test database with Reminder schema (lazy initialization)
    public static func withReminderSchema() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withReminderSchema)
    }

    /// Creates a test database with Reminder schema and sample data (lazy initialization)
    public static func withReminderData() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withReminderData)
    }
}
