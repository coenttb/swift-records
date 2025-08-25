import Foundation
import StructuredQueries
import StructuredQueriesPostgres
import PostgresNIO
import Logging

extension Database {
    /// Internal wrapper to bridge to PostgresConnection
    struct Connection: DatabaseProtocol {
        let postgres: PostgresConnection
        let logger: Logger
        
        init(_ postgres: PostgresConnection, logger: Logger? = nil) {
            self.postgres = postgres
            self.logger = logger ?? Logger(label: "records.connection")
        }
        
        func execute(_ statement: some Statement<()>) async throws {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else { return }
            
            let postgresStatement = PostgresStatement(queryFragment: queryFragment)
            _ = try await postgres.query(
                postgresStatement.query,
                logger: logger
            )
        }
        
        func execute(_ sql: String) async throws {
            let query = PostgresQuery(unsafeSQL: sql)
            _ = try await postgres.query(query, logger: logger)
        }
        
        func executeFragment(_ fragment: QueryFragment) async throws {
            let postgresStatement = PostgresStatement(queryFragment: fragment)
            _ = try await postgres.query(
                postgresStatement.query,
                logger: logger
            )
        }
        
        func fetchAll<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> [QueryValue.QueryOutput] {
            let queryFragment = statement.query
            guard !queryFragment.isEmpty else { return [] }
            
            let postgresStatement = PostgresStatement(queryFragment: queryFragment)
            let rows = try await postgres.query(
                postgresStatement.query,
                logger: logger
            )
            
            var results: [QueryValue.QueryOutput] = []
            for try await row in rows {
                var decoder = PostgresQueryDecoder(row: row)
                let value = try decoder.decodeColumns(QueryValue.self)
                results.append(value)
            }
            return results
        }
        
        func fetchOne<QueryValue: QueryRepresentable>(
            _ statement: some Statement<QueryValue>
        ) async throws -> QueryValue.QueryOutput? {
            let results = try await fetchAll(statement)
            return results.first
        }
    }
}