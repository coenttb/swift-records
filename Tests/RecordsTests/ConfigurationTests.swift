import Dependencies
import DependenciesTestSupport
import EnvironmentVariables
import Foundation
import PostgresNIO
@testable import Records
import Testing

@Suite(
    "Configuration",
    .dependency(\.envVars, .development)
)
struct ConfigurationTests {

    @Test("Configuration from environment variables")
    func testConfigurationFromEnvironment() async throws {

        let config = try PostgresClient.Configuration.fromEnvironment()

        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "swift-records-development")
        #expect(config.username == "admin")
        #expect(config.password == "")
    }

    @Test("Database single connection initialization")
    func testDatabaseQueueInitialization() async throws {
        let config = try PostgresClient.Configuration.fromEnvironment()

        do {
            let queue = await Database.singleConnection(configuration: config)

            // Test that we can perform operations
            try await queue.write { db in
                try await db.execute("SELECT 1")
            }

            try await queue.close()
        } catch {
            throw error
        }
    }

    @Test("Database.Pool initialization with pooling")
    func testDatabasePoolInitialization() async throws {
        let config = try PostgresClient.Configuration.fromEnvironment()

        let pool = await Database.pool(
            configuration: config,
            minConnections: 2,
            maxConnections: 5
        )

        // Test that we can perform operations
        try await pool.read { db in
            try await db.execute("SELECT 1")
        }

        try await pool.close()
    }

    @Test("Configuration stores values correctly")
    func testConfigurationValues() async throws {
        let config = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "admin",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "database-postgres-dev")
        #expect(config.username == "admin")
        #expect(config.password == nil)
    }

    @Test("Connection factory methods")
    func testConnectionStrategies() async throws {
        // Test single connection
        let singleConfig = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "admin",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        let single = await Database.singleConnection(configuration: singleConfig)
        // Just verify it was created
        #expect(single != nil)
        try await single.close()

        // Test pool connection
        let poolConfig = PostgresClient.Configuration(
            host: "localhost",
            port: 5432,
            username: "admin",
            password: nil,
            database: "database-postgres-dev",
            tls: .disable
        )

        let pool = await Database.pool(
            configuration: poolConfig,
            minConnections: 3,
            maxConnections: 10
        )
        #expect(pool != nil)
        try await pool.close()
    }
}
