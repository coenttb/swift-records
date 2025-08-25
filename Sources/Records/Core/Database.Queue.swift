import Foundation
import PostgresNIO
import Logging

// MARK: - Database.Queue

extension Database {
    /// A database connection that serializes database accesses.
    ///
    /// `Database.Queue` provides a simple interface for database operations with serial execution.
    /// All database operations are executed sequentially, making it suitable for most applications.
    public actor Queue: Writer {
        private let connection: PostgresConnection
        private let logger: Logger
        private var isClosed = false
        
        /// Initialize with a PostgreSQL configuration.
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
        
        /// Initialize with environment variables.
        public init() async throws {
            try await self.init(configuration: .fromEnvironment())
        }
        
        /// Performs a read-only database operation.
        public func read<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            let db = Database.Connection(connection, logger: logger)
            return try await block(db)
        }
        
        /// Performs a database operation that can write.
        public func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            let db = Database.Connection(connection, logger: logger)
            return try await block(db)
        }
        
        /// Close the database connection.
        public func close() async throws {
            guard !isClosed else { return }
            isClosed = true
            try await connection.close()
        }
    }
}