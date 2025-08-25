import Foundation
import StructuredQueries
import StructuredQueriesPostgres

extension Database {
    /// Internal wrapper to bridge to PostgresQueryDatabase
    struct Connection: DatabaseProtocol {
        let postgres: PostgresQueryDatabase
        
        init(_ postgres: PostgresQueryDatabase) {
            self.postgres = postgres
        }
        
        func execute(_ statement: some Statement<()>) async throws {
            try await postgres.execute(statement)
        }
        
        func execute(_ sql: String) async throws {
            _ = try await postgres.execute(sql)
        }
        
        func executeFragment(_ fragment: QueryFragment) async throws {
            try await postgres.executeFragment(fragment)
        }
        
        func fetchAll<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> [QueryValue.QueryOutput] {
            try await postgres.execute(statement)
        }
        
        func fetchOne<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> QueryValue.QueryOutput? {
            let results = try await postgres.execute(statement)
            return results.first
        }
    }
}