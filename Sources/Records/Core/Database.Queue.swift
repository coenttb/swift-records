import Foundation
import PostgresNIO
import Logging

// MARK: - Database.Queue

extension Database {
    /// A database connection that serializes database accesses.
    ///
    /// `Database.Queue` provides a simple interface for database operations with serial execution.
    /// All database operations are executed sequentially using a single connection, making it
    /// suitable for development, testing, and applications with moderate concurrency requirements.
    ///
    /// ## Characteristics
    ///
    /// - Single connection to the database
    /// - All operations are serialized (no concurrent queries)
    /// - Lower memory footprint than connection pooling
    /// - Ideal for development and testing
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Configure at app startup
    /// try await prepareDependencies {
    ///     $0.defaultDatabase = try await Database.Queue(
    ///         configuration: .fromEnvironment()
    ///     )
    /// }
    ///
    /// // Use in your app
    /// @Dependency(\.defaultDatabase) var db
    ///
    /// let users = try await db.read { db in
    ///     try await User.fetchAll(db)
    /// }
    /// ```
    public actor Queue: Writer {
        private let connection: PostgresConnection
        private let logger: Logger
        private var isClosed = false
        
        /// Initializes a database queue with the specified configuration.
        ///
        /// - Parameter configuration: The database configuration.
        /// - Throws: Connection errors if unable to connect to the database.
        public init(configuration: Configuration) async throws {
            let pgConfig = PostgresConnection.Configuration(
                host: configuration.host,
                port: configuration.port,
                username: configuration.username,
                password: configuration.password,
                database: configuration.database,
                tls: configuration.tls
            )
            
            self.logger = Logger(label: "records.queue")
            self.connection = try await PostgresConnection.connect(
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
        }
        
        /// Initializes a database queue using environment variables.
        ///
        /// See ``Configuration/fromEnvironment(connectionStrategy:)`` for required
        /// environment variables.
        ///
        /// - Throws: Configuration or connection errors.
        public init() async throws {
            try await self.init(configuration: .fromEnvironment())
        }
        
        /// Performs a read-only database operation.
        ///
        /// Although this is a read method, Queue executes all operations
        /// on the same connection serially.
        public func read<T: Sendable>(_ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T) async throws -> T {
            let db = Database.Connection(connection, logger: logger)
            return try await block(db)
        }
        
        /// Performs a database operation that can write.
        ///
        /// Write operations are executed on the same connection as reads,
        /// ensuring serial execution.
        public func write<T: Sendable>(_ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T) async throws -> T {
            let db = Database.Connection(connection, logger: logger)
            return try await block(db)
        }
        
        /// Closes the database connection.
        ///
        /// After closing, the queue cannot be used for further operations.
        /// This is typically called during app shutdown.
        public func close() async throws {
            guard !isClosed else { return }
            isClosed = true
            try await connection.close()
        }
    }
}
