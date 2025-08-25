import Foundation
import StructuredQueriesPostgres
import PostgresNIO
import Logging

// MARK: - Database.Pool

extension Database {
    /// A database connection pool that allows concurrent database accesses.
    ///
    /// `Database.Pool` manages multiple PostgreSQL connections and provides concurrent read access
    /// while serializing write operations.
    public final class Pool: Writer, Sendable {
        private let postgres: PostgresQueryDatabase
        private let writeSerializer = WriteSerializer()
        
        /// Initialize with a PostgreSQL configuration with pooling enabled.
        public init(
            configuration: PostgresQueryDatabase.Configuration,
            minConnections: Int = 2,
            maxConnections: Int = 10
        ) async throws {
            let poolingConfig = PostgresQueryDatabase.Configuration(
                host: configuration.host,
                port: configuration.port,
                database: configuration.database,
                username: configuration.username,
                password: configuration.password,
                tls: configuration.tls,
                pooling: .enabled(min: minConnections, max: maxConnections)
            )
            self.postgres = try await PostgresQueryDatabase.configure(poolingConfig)
        }
        
        /// Initialize with environment variables and pooling enabled.
        public convenience init(
            minConnections: Int = 2,
            maxConnections: Int = 10
        ) async throws {
            let config = PostgresQueryDatabase.Configuration.fromEnvironment(
                pooling: .enabled(min: minConnections, max: maxConnections)
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
            let db = Database.Connection(postgres)
            return try await block(db)
        }
        
        /// Performs a database operation that can write.
        /// Write operations are serialized.
        public func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            try await writeSerializer.perform {
                let db = Database.Connection(postgres)
                return try await block(db)
            }
        }
        
        /// Close all database connections in the pool.
        public func close() async throws {
            try await writeSerializer.perform {
                try await postgres.close()
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
}