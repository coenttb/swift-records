import Foundation

extension Database {
    /// A database reader provides read-only database access.
    public protocol Reader: Sendable {
        /// Performs a read-only database operation.
        func read<T: Sendable>(_ block: @Sendable (any DatabaseProtocol) async throws -> T) async throws -> T
    }
}