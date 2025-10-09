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
            guard shouldCleanup else { return }

            do {
                // Drop the schema first
                try await wrapped.write { db in
                    try await db.execute("DROP SCHEMA IF EXISTS \(schemaName) CASCADE")
                }
            } catch {
                // Ignore schema drop errors silently
            }

            // Always try to close the connection, even if schema drop failed
            do {
                if let runner = wrapped as? Database.ClientRunner {
                    try await runner.close()
                }
            } catch {
                // Ignore close errors silently
            }
        }

        public func close() async throws {
            await self.cleanup()
        }

        deinit {
            // Note: Can't do async cleanup in deinit
            // Tests should call cleanup() explicitly or use withTestDatabase
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

        // Create connection
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()
        let database = await Database.singleConnection(configuration: config)

        // Create and use test schema
        try await database.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: database,
            schemaName: schemaName
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

        // Create connection pool
        let config = try configuration ?? PostgresClient.Configuration.fromEnvironment()
        let pool = await Database.pool(
            configuration: config,
            minConnections: minConnections,
            maxConnections: maxConnections
        )

        // Create and use test schema
        try await pool.write { db in
            try await db.execute("CREATE SCHEMA \(schemaName)")
            try await db.execute("SET search_path TO \(schemaName)")
        }

        return TestDatabase(
            wrapped: pool,
            schemaName: schemaName
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
