import Dependencies
import DependenciesTestSupport
import EnvironmentVariables
import Foundation
import PostgresNIO
import Records
import Testing

@Suite("Configuration")
struct ConfigurationTests {

  @Test("Configuration from environment variables")
  func testConfigurationFromEnvironment() async throws {
    // This test verifies that PostgresClient.Configuration.fromEnvironment() can successfully
    // create a configuration when environment variables are properly set.
    // The actual values vary by environment (local dev vs CI), so we just verify
    // that the configuration can be created without throwing an error.
    let config = try PostgresClient.Configuration.fromEnvironment()

    // Verify standard port is used
    #expect(config.port == 5432)
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
      username: "coenttb",
      password: nil,
      database: "database-postgres-dev",
      tls: .disable
    )

    #expect(config.host == "localhost")
    #expect(config.port == 5432)
    #expect(config.database == "database-postgres-dev")
    #expect(config.username == "coenttb")
    #expect(config.password == nil)
  }

  @Test("Connection factory methods")
  func testConnectionStrategies() async throws {
    // Test single connection
    let singleConfig = PostgresClient.Configuration(
      host: "localhost",
      port: 5432,
      username: "coenttb",
      password: nil,
      database: "database-postgres-dev",
      tls: .disable
    )

    let single = await Database.singleConnection(configuration: singleConfig)
    // Just verify it was created
    try await single.close()

    // Test pool connection
    let poolConfig = PostgresClient.Configuration(
      host: "localhost",
      port: 5432,
      username: "coenttb",
      password: nil,
      database: "database-postgres-dev",
      tls: .disable
    )

    let pool = await Database.pool(
      configuration: poolConfig,
      minConnections: 3,
      maxConnections: 10
    )
    try await pool.close()
  }
}
