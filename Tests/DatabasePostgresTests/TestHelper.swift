import Foundation
import Testing
@testable import DatabasePostgres
import StructuredQueriesPostgres
import Dependencies
import EnvironmentVariables
import PostgresNIO
import Logging
import ConcurrencyExtras

// MARK: - Test Database Storage

// Global storage to keep the database connection alive throughout test suite
private final class TestDatabaseStorage: @unchecked Sendable {
    static let shared = TestDatabaseStorage()
    private var queue: Database.Queue?
    private var pool: Database.Pool?
    private var tablesCreated = false
    private let lock = NSLock()
    
    init() {
        // Singleton initialized
    }
    
    func areTablesCreated() -> Bool {
        lock.withLock { tablesCreated }
    }
    
    func markTablesCreated() {
        lock.withLock { tablesCreated = true }
    }
    
    func markTablesDropped() {
        lock.withLock { tablesCreated = false }
    }
    
    func getQueue() async throws -> Database.Queue {
        // First check if we already have a queue
        if let existingQueue = lock.withLock({ self.queue }) {
            return existingQueue
        }
        
        // Create queue using configuration
        let config = try Database.Configuration.fromEnvironment(connectionStrategy: .single)
        let newQueue = try await Database.Queue(configuration: config.postgresConfiguration)
        
        // Store the queue, but check again in case another task created one
        return lock.withLock {
            // If another task created a queue while we were creating ours,
            // we need to close the one we just created and use the existing one
            if let existingQueue = self.queue {
                // We need to close the queue we just created to avoid the deallocation issue
                Task {
                    try? await newQueue.close()
                }
                return existingQueue
            }
            
            // Store our new queue
            self.queue = newQueue
            return newQueue
        }
    }
    
    func getPool() async throws -> Database.Pool {
        // First check if we already have a pool
        if let existingPool = lock.withLock({ self.pool }) {
            return existingPool
        }
        
        // Create pool using configuration
        let config = try Database.Configuration.fromEnvironment(connectionStrategy: .pool(min: 2, max: 5))
        let newPool = try await Database.Pool(
            configuration: config.postgresConfiguration,
            minConnections: 2,
            maxConnections: 5
        )
        
        // Store the pool, but check again in case another task created one
        return lock.withLock {
            // If another task created a pool while we were creating ours,
            // we need to close the one we just created and use the existing one
            if let existingPool = self.pool {
                // We need to close the pool we just created to avoid the deallocation issue
                Task {
                    try? await newPool.close()
                }
                return existingPool
            }
            
            // Store our new pool
            self.pool = newPool
            return newPool
        }
    }
    
    func cleanup() async {
        // Don't close connections during tests - let them persist
        // This prevents "PostgresConnection deinitialized before being closed" errors
        // The connections will be closed when the test suite ends
    }
    
    /// Force close all connections (call at end of test suite if needed)
    func forceCloseAll() async {
        let (queue, pool) = lock.withLock {
            let q = self.queue
            let p = self.pool
            self.queue = nil
            self.pool = nil
            return (q, p)
        }
        
        // Close them outside the lock
        if let queue = queue {
            try? await queue.close()
        }
        if let pool = pool {
            try? await pool.close()
        }
    }
    
    deinit {
        // Note: Can't close connection in deinit since it needs async
        // The connection will show a warning but tests will work
    }
}

// MARK: - Test Database Setup

struct TestDatabase {
    
    /// Creates a test database with clean state
    static func makeTestDatabase() async throws -> any Database.Writer {
        return try await TestDatabaseStorage.shared.getQueue()
    }
    
    /// Creates a test database pool
    static func makeTestPool() async throws -> any Database.Writer {
        return try await TestDatabaseStorage.shared.getPool()
    }
    
    /// Sets up test tables once for the entire test suite (idempotent)
    static func setupTestTables(_ database: any Database.Writer) async throws {
        // Skip if already created
        if TestDatabaseStorage.shared.areTablesCreated() {
            return
        }
        
        // First, drop any existing tables to ensure clean state
        // This handles schema changes during development
        try await dropExistingTables(database)
        
        // Use raw SQL with IF NOT EXISTS for idempotency
        // This avoids migration conflicts
        try await database.write { db in
            // Create users table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE NOT NULL,
                    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            // Create posts table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS posts (
                    id SERIAL PRIMARY KEY,
                    "userId" INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    "publishedAt" TIMESTAMP
                )
            """)
            
            // Create comments table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS comments (
                    id SERIAL PRIMARY KEY,
                    "postId" INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
                    "userId" INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,
                    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            // Create tags table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS tags (
                    id SERIAL PRIMARY KEY,
                    name TEXT UNIQUE NOT NULL
                )
            """)
            
            // Create post_tags junction table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS post_tags (
                    "postId" INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
                    "tagId" INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY ("postId", "tagId")
                )
            """)
        }
        
        TestDatabaseStorage.shared.markTablesCreated()
    }
    
    /// Truncates all test tables to provide clean state for each test
    static func truncateTestTables(_ database: any Database.Writer) async throws {
        try await database.write { db in
            // Truncate in reverse dependency order
            // CASCADE will handle foreign key constraints
            try await db.execute("TRUNCATE TABLE post_tags, comments, posts, tags, users RESTART IDENTITY CASCADE")
        }
    }
    
    /// Prepares database for a test - ensures tables exist and are empty
    static func prepareForTest(_ database: any Database.Writer) async throws {
        // Ensure tables exist
        try await setupTestTables(database)
        
        // Clear all data
        try await truncateTestTables(database)
    }
    
    /// Helper to drop existing tables for schema changes during development
    private static func dropExistingTables(_ database: any Database.Writer) async throws {
        try await database.write { db in
            try await db.execute("DROP TABLE IF EXISTS post_tags CASCADE")
            try await db.execute("DROP TABLE IF EXISTS comments CASCADE")
            try await db.execute("DROP TABLE IF EXISTS posts CASCADE")
            try await db.execute("DROP TABLE IF EXISTS tags CASCADE")
            try await db.execute("DROP TABLE IF EXISTS users CASCADE")
            try await db.execute("DROP TABLE IF EXISTS __database_migrations CASCADE")
        }
        TestDatabaseStorage.shared.markTablesDropped()
    }
    
    /// Alias for backwards compatibility
    static func cleanupTestTables(_ database: any Database.Writer) async throws {
        // Just truncate, don't drop
        try await truncateTestTables(database)
    }
    
    /// Inserts sample data for testing
    static func insertSampleData(_ database: any Database.Writer) async throws {
        try await database.write { db in
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

