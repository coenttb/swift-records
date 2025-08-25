import Foundation

extension Database {
    /// A database writer provides read-write database access.
    public protocol Writer: Reader, Sendable {
        /// Performs a database operation that can write.
        func write<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T
    }
}