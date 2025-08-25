import Foundation
import PostgresNIO
import Logging

// MARK: - Database.Pool

extension Database {
    /// A database connection pool that allows concurrent database accesses.
    ///
    /// `Database.Pool` manages multiple PostgreSQL connections, providing concurrent read access
    /// while serializing write operations. This is ideal for production applications with
    /// high concurrency requirements.
    ///
    /// ## Characteristics
    ///
    /// - Multiple connections (configurable min/max)
    /// - Concurrent read operations
    /// - Serialized write operations
    /// - Automatic connection lifecycle management
    /// - Connection health validation
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Configure at app startup
    /// try await prepareDependencies {
    ///     $0.defaultDatabase = try await Database.Pool(
    ///         configuration: .fromEnvironment(),
    ///         minConnections: 5,
    ///         maxConnections: 20
    ///     )
    /// }
    ///
    /// // Concurrent reads are supported
    /// async let users = db.read { db in
    ///     try await User.fetchAll(db)
    /// }
    /// async let posts = db.read { db in
    ///     try await Post.fetchAll(db)
    /// }
    /// let (allUsers, allPosts) = try await (users, posts)
    /// ```
    public final class Pool: Writer, Sendable {
        private let pool: ConnectionPool
        private let writeSerializer = WriteSerializer()
        private let closeState = CloseState()
        private let logger: Logger
        
        /// Initializes a connection pool with the specified configuration.
        ///
        /// - Parameters:
        ///   - configuration: The database configuration.
        ///   - minConnections: Minimum number of connections to maintain (default: 2).
        ///   - maxConnections: Maximum number of connections allowed (default: 10).
        /// - Throws: Connection errors if unable to establish the minimum connections.
        public init(
            configuration: Configuration,
            minConnections: Int = 2,
            maxConnections: Int = 10
        ) async throws {
            let pgConfig = PostgresConnection.Configuration(
                host: configuration.host,
                port: configuration.port,
                username: configuration.username,
                password: configuration.password,
                database: configuration.database,
                tls: configuration.tls
            )
            
            self.logger = Logger(label: "records.pool")
            self.pool = try await ConnectionPool(
                configuration: pgConfig,
                minConnections: minConnections,
                maxConnections: maxConnections
            )
        }
        
        /// Initializes a connection pool using environment variables.
        ///
        /// See ``Configuration/fromEnvironment(connectionStrategy:)`` for required
        /// environment variables.
        ///
        /// - Parameters:
        ///   - minConnections: Minimum number of connections to maintain (default: 2).
        ///   - maxConnections: Maximum number of connections allowed (default: 10).
        /// - Throws: Configuration or connection errors.
        public convenience init(
            minConnections: Int = 2,
            maxConnections: Int = 10
        ) async throws {
            let config = try Configuration.fromEnvironment(
                connectionStrategy: .pool(min: minConnections, max: maxConnections)
            )
            try await self.init(
                configuration: config,
                minConnections: minConnections,
                maxConnections: maxConnections
            )
        }
        
        /// Performs a read-only database operation.
        ///
        /// Multiple read operations can execute concurrently using different
        /// connections from the pool. This provides better performance for
        /// read-heavy applications.
        ///
        /// - Parameter block: The read operation to perform.
        /// - Returns: The value returned by the block.
        public func read<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            try await pool.withConnection { connection in
                let db = Database.Connection(connection, logger: logger)
                return try await block(db)
            }
        }
        
        /// Performs a database operation that can write.
        ///
        /// Write operations are serialized to prevent conflicts, while still
        /// using connections from the pool. This ensures data consistency
        /// while maintaining connection efficiency.
        ///
        /// - Parameter block: The write operation to perform.
        /// - Returns: The value returned by the block.
        public func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            try await writeSerializer.perform {
                try await pool.withConnection { connection in
                    let db = Database.Connection(connection, logger: logger)
                    return try await block(db)
                }
            }
        }
        
        /// Closes all database connections in the pool.
        ///
        /// After closing, the pool cannot be used for further operations.
        /// This is typically called during app shutdown.
        ///
        /// - Throws: Errors if connections cannot be properly closed.
        public func close() async throws {
            let alreadyClosed = await closeState.markClosed()
            guard !alreadyClosed else { return }
            
            try await writeSerializer.perform {
                try await pool.shutdown()
            }
        }
    }
}

// MARK: - WriteSerializer

extension Database.Pool {
    /// Internal actor to serialize write operations
    private actor WriteSerializer {
        func perform<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
            try await operation()
        }
    }
    
    /// Internal actor to manage close state thread-safely
    private actor CloseState {
        private var closed = false
        
        var isClosed: Bool {
            closed
        }
        
        func markClosed() -> Bool {
            let wasClosed = closed
            closed = true
            return wasClosed
        }
    }
}