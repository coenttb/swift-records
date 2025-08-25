import Foundation
import Testing
@testable import DatabasePostgres
import StructuredQueriesPostgres
import Dependencies
import EnvironmentVariables

// MARK: - Test Database Setup

struct TestDatabase {
    /// Creates a test database with clean state
    static func makeTestDatabase() async throws -> any Database.Writer {
        // Load environment variables from .env.development
        @Dependency(\.envVars) var envVars
        
        let config = try Database.Configuration(
            host: envVars["DATABASE_HOST"] ?? "localhost",
            port: envVars["DATABASE_PORT"].flatMap(Int.init) ?? 5432,
            database: envVars["DATABASE_NAME"] ?? "database-postgres-dev",
            username: envVars["DATABASE_USER"] ?? "Admin",
            password: envVars["DATABASE_PASSWORD"],
            connectionStrategy: .single
        )
        
        return try await Database.Queue(configuration: config.postgresConfiguration)
    }
    
    /// Creates a test database pool
    static func makeTestPool() async throws -> any Database.Writer {
        let config = try Database.Configuration.fromEnvironment(
            connectionStrategy: .pool(min: 2, max: 5)
        )
        
        return try await Database.Pool(
            configuration: config.postgresConfiguration,
            minConnections: 2,
            maxConnections: 5
        )
    }
    
    /// Sets up test tables
    static func setupTestTables(_ database: any Database.Writer) async throws {
        var migrator = Database.Migrator()
        
        migrator.registerMigration("Create test tables") { db in
            // Create users table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            // Create posts table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS posts (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id),
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    published_at TIMESTAMP
                )
            """)
            
            // Create comments table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS comments (
                    id SERIAL PRIMARY KEY,
                    post_id INTEGER NOT NULL REFERENCES posts(id),
                    user_id INTEGER NOT NULL REFERENCES users(id),
                    text TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
                    post_id INTEGER NOT NULL REFERENCES posts(id),
                    tag_id INTEGER NOT NULL REFERENCES tags(id),
                    PRIMARY KEY (post_id, tag_id)
                )
            """)
        }
        
        try await migrator.migrate(database)
    }
    
    /// Cleans up test tables
    static func cleanupTestTables(_ database: any Database.Writer) async throws {
        try await database.write { db in
            try await db.execute("DROP TABLE IF EXISTS post_tags CASCADE")
            try await db.execute("DROP TABLE IF EXISTS comments CASCADE")
            try await db.execute("DROP TABLE IF EXISTS posts CASCADE")
            try await db.execute("DROP TABLE IF EXISTS tags CASCADE")
            try await db.execute("DROP TABLE IF EXISTS users CASCADE")
            try await db.execute("DROP TABLE IF EXISTS __database_migrations CASCADE")
        }
    }
    
    /// Inserts sample data for testing
    static func insertSampleData(_ database: any Database.Writer) async throws {
        try await database.write { db in
            // Insert users using Draft type
            try await User.insert {
                User.Draft(name: "Alice", email: "alice@example.com", createdAt: Date())
            }.execute(db)
            
            try await User.insert {
                User.Draft(name: "Bob", email: "bob@example.com", createdAt: Date())
            }.execute(db)
            
            // Insert posts using Draft type
            try await Post.insert {
                Post.Draft(userId: 1, title: "First Post", content: "Hello World", publishedAt: Date())
            }.execute(db)
            
            try await Post.insert {
                Post.Draft(userId: 2, title: "Second Post", content: "Another post", publishedAt: nil)
            }.execute(db)
            
            // Insert comments using Draft type
            try await Comment.insert {
                Comment.Draft(postId: 1, userId: 2, text: "Great post!", createdAt: Date())
            }.execute(db)
            
            // Insert tags using Draft type
            try await Tag.insert {
                Tag.Draft(name: "Swift")
            }.execute(db)
            
            try await Tag.insert {
                Tag.Draft(name: "Database")
            }.execute(db)
            
            // Insert post-tag relationships
            try await PostTag.insert {
                PostTag(postId: 1, tagId: 1)
            }.execute(db)
            
            try await PostTag.insert {
                PostTag(postId: 1, tagId: 2)
            }.execute(db)
        }
    }
}

