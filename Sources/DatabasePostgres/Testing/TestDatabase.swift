import Foundation
import StructuredQueries
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
            _ block: @Sendable (any DatabaseProtocol) async throws -> T
        ) async throws -> T {
            try await wrapped.read(block)
        }
        
        public func write<T: Sendable>(
            _ block: @Sendable (any DatabaseProtocol) async throws -> T
        ) async throws -> T {
            try await wrapped.write(block)
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
                // Ignore schema drop errors
                print("Warning: Failed to drop test schema \(schemaName): \(error)")
            }
            
            // Always try to close the connection, even if schema drop failed
            do {
                if let queue = wrapped as? Database.Queue {
                    try await queue.close()
                } else if let pool = wrapped as? Database.Pool {
                    try await pool.close()
                }
            } catch {
                // Ignore close errors
                print("Warning: Failed to close connection: \(error)")
            }
        }
        
        deinit {
            // Note: Can't do async cleanup in deinit
            // Tests should call cleanup() explicitly or use withTestDatabase
        }
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
        configuration: Configuration? = nil,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"
        
        // Create connection
        let config = try configuration ?? Configuration.fromEnvironment()
        let database = try await Database.Queue(configuration: config.postgresConfiguration)
        
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
        configuration: Configuration? = nil,
        minConnections: Int = 2,
        maxConnections: Int = 5,
        prefix: String = "test"
    ) async throws -> TestDatabase {
        // Generate unique schema name
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let schemaName = "\(prefix)_\(uuid)"
        
        // Create connection pool
        let config = try configuration ?? Configuration.fromEnvironment(
            connectionStrategy: .pool(min: minConnections, max: maxConnections)
        )
        let pool = try await Database.Pool(
            configuration: config.postgresConfiguration,
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
        configuration: Configuration? = nil,
        prefix: String = "test",
        _ block: (TestDatabase) async throws -> T
    ) async throws -> T {
        let database = try await testDatabase(
            configuration: configuration,
            prefix: prefix
        )
        
        defer {
            Task {
                await database.cleanup()
            }
        }
        
        return try await block(database)
    }
}