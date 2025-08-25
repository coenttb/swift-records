import Foundation
import PostgresNIO
import Logging

// MARK: - Database.Pool

extension Database {
    /// A database connection pool that allows concurrent database accesses.
    ///
    /// `Database.Pool` manages multiple PostgreSQL connections and provides concurrent read access
    /// while serializing write operations.
    public final class Pool: Writer, Sendable {
        private let pool: ConnectionPool
        private let writeSerializer = WriteSerializer()
        private let closeState = CloseState()
        private let logger: Logger
        
        /// Initialize with a PostgreSQL configuration with pooling enabled.
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
        
        /// Initialize with environment variables and pooling enabled.
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
        /// Multiple reads can execute concurrently.
        public func read<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            try await pool.withConnection { connection in
                let db = Database.Connection(connection, logger: logger)
                return try await block(db)
            }
        }
        
        /// Performs a database operation that can write.
        /// Write operations are serialized.
        public func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            try await writeSerializer.perform {
                try await pool.withConnection { connection in
                    let db = Database.Connection(connection, logger: logger)
                    return try await block(db)
                }
            }
        }
        
        /// Close all database connections in the pool.
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