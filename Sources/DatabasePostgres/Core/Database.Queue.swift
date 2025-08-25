import Foundation
import StructuredQueriesPostgres
import PostgresNIO
import Logging

// MARK: - Database.Queue

extension Database {
    /// A database connection that serializes database accesses.
    ///
    /// `Database.Queue` provides a simple interface for database operations with serial execution.
    /// All database operations are executed sequentially, making it suitable for most applications.
    public actor Queue: Writer {
        private let postgres: PostgresQueryDatabase
        
        /// Initialize with a PostgreSQL configuration.
        public init(configuration: PostgresQueryDatabase.Configuration) async throws {
            self.postgres = try await PostgresQueryDatabase.configure(configuration)
        }
        
        /// Initialize with environment variables.
        public init() async throws {
            self.postgres = try await PostgresQueryDatabase.configure(.fromEnvironment())
        }
        
        /// Performs a read-only database operation.
        public func read<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            let db = Database.Connection(postgres)
            return try await block(db)
        }
        
        /// Performs a database operation that can write.
        public func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T {
            let db = Database.Connection(postgres)
            return try await block(db)
        }
        
        /// Close the database connection.
        public func close() async throws {
            try await postgres.close()
        }
    }
}