import Foundation
import StructuredQueries

/// A type that provides database access.
///
/// This protocol is the main interface for executing database operations.
/// It's implemented by both `Database.Queue` (serial access) and `Database.Pool` (concurrent access).
public protocol DatabaseProtocol: Sendable {
    /// Execute a statement that doesn't return any values.
    func execute(_ statement: some Statement<()>) async throws
    
    /// Execute a raw SQL string.
    func execute(_ sql: String) async throws
    
    /// Execute a query fragment.
    func executeFragment(_ fragment: QueryFragment) async throws
    
    /// Fetch all results from a statement.
    func fetchAll<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> [QueryValue.QueryOutput]
    
    /// Fetch a single result from a statement.
    func fetchOne<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> QueryValue.QueryOutput?
}