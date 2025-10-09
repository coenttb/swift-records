import Foundation
import PostgresNIO
import StructuredQueriesPostgres

extension Database {
    /// A test database wrapper that provides schema isolation for tests
    public final class TestDatabase: Writer, @unchecked Sendable {
        private let wrapped: any Writer
        private let schemaName: String
        private let shouldCleanup: Bool

        init(
            wrapped: any Writer,
            schemaName: String,
            shouldCleanup: Bool = true
        ) {
            self.wrapped = wrapped
            self.schemaName = schemaName
            self.shouldCleanup = shouldCleanup
        }

        deinit {
            // Schema will persist for process lifetime (acceptable for tests)
            // Cleanup would cause hang due to ClientRunner deinit
        }

        public func read<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await wrapped.read { db in
                // Ensure schema is set for this connection
                try await db.execute("SET search_path TO \(schemaName)")
                return try await block(db)
            }
        }

        public func write<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await wrapped.write { db in
                // Ensure schema is set for this connection
                try await db.execute("SET search_path TO \(schemaName)")
                return try await block(db)
            }
        }

        /// Clean up the test schema
        public func cleanup() async {
            guard shouldCleanup else {
                return
            }

            do {
                // Drop the schema first
                try await wrapped.write { db in
                    try await db.execute("DROP SCHEMA IF EXISTS \(schemaName) CASCADE")
                }
            } catch {
                // Ignore cleanup errors
            }

            // Always try to close the connection, even if schema drop failed
            do {
                try await wrapped.close()
            } catch {
                // Ignore cleanup errors
            }
        }

        public func close() async throws {
            await self.cleanup()
        }
    }
}

// MARK: - Setup Mode

extension Database {
    /// Setup mode for test databases
    public enum TestDatabaseSetupMode: Sendable {
        /// Empty database (no tables)
        case empty
        /// User/Post schema (swift-records-specific tests)
        case withSchema
        /// User/Post schema with sample data
        case withSampleData
        /// Reminder schema (matches upstream swift-structured-queries)
        case withReminderSchema
        /// Reminder schema with sample data
        case withReminderData
    }
}

// MARK: - Factory Methods

extension Database {
    /// Creates a test database with an isolated schema
    ///
    /// Each call creates a new schema with a unique name, providing complete isolation
    /// for test suites. The schema is automatically set as the search path.
    ///
    /// - Parameters:
    ///   - configuration: Optional database configuration. Uses environment if not provided.
    ///   - prefix: Optional prefix for the schema name (default: "test")
    /// - Returns: A test database with isolated schema
    public static func testDatabase(
        configuration: PostgresClient.Configuration? = nil,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"

        // Create direct connection without background tasks
        // This prevents hanging on test exit
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()
        let database = try await TestConnection(configuration: config)

        // Create and use test schema
        try await database.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: database,
            schemaName: schemaName,
            shouldCleanup: false
        )
    }

    /// Creates a test database pool with an isolated schema
    public static func testDatabasePool(
        configuration: PostgresClient.Configuration? = nil,
        minConnections: Int = 2,
        maxConnections: Int = 5,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"

        // For test pool, just create multiple single connections
        // This prevents hanging on test exit from background tasks
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()

        // For simplicity in tests, use a single connection even for "pool"
        // Real pooling not needed for tests
        let pool = try await TestConnection(configuration: config)

        // Create and use test schema
        try await pool.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: pool,
            schemaName: schemaName,
            shouldCleanup: false
        )
    }
}

// MARK: - Convenience

extension Database {
    /// Executes a block with a test database, automatically cleaning up afterward
    public static func withTestDatabase<T>(
        configuration: PostgresClient.Configuration? = nil,
        prefix: String = "test",
        _ block: (TestDatabase) async throws -> T
    ) async throws -> T {
        let database = try await testDatabase(
            configuration: configuration,
            prefix: prefix
        )

        do {
            let result = try await block(database)
            await database.cleanup()
            return result
        } catch {
            await database.cleanup()
            throw error
        }
    }
}
