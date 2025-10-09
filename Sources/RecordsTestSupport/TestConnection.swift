import Foundation
import Logging
import NIOCore
import PostgresNIO
@testable import Records

/// A simple test database connection without background tasks
///
/// Unlike ClientRunner which uses PostgresClient with an event loop task,
/// this uses a single PostgresConnection directly. This allows tests to
/// exit cleanly without hanging on background tasks.
///
/// **Current Status**: Process exits cleanly but queries fail with PSQLError.
/// PostgresConnection appears to need the client.run() event loop to function.
final class TestConnection: Database.Writer, @unchecked Sendable {
    private let connection: PostgresConnection

    init(configuration: PostgresClient.Configuration) async throws {
        // For tests, just use .disable TLS for simplicity
        // Tests run against local PostgreSQL which typically doesn't need TLS
        let connConfig = PostgresConnection.Configuration(
            host: configuration.host ?? "localhost",
            port: configuration.port ?? 5432,
            username: configuration.username,
            password: configuration.password,
            database: configuration.database,
            tls: .disable
        )

        // Create a single connection directly
        self.connection = try await PostgresConnection.connect(
            on: MultiThreadedEventLoopGroup.singleton.next(),
            configuration: connConfig,
            id: 1,
            logger: Logger(label: "test-connection")
        )
    }

    func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let conn = Database.Connection(connection)
        return try await block(conn)
    }

    func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        let conn = Database.Connection(connection)
        return try await block(conn)
    }

    func close() async throws {
        try await connection.close()
    }
}
