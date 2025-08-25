import Testing
import Foundation
@testable import DatabasePostgres
import Dependencies
import EnvironmentVariables
import DependenciesTestSupport

@Suite(
    "Configuration",
    .dependency(\.envVars, .development),
    .serialized
)
struct ConfigurationTests {
    
    @Test("Configuration from environment variables")
    func testConfigurationFromEnvironment() async throws {
        
        let config = try Database.Configuration.fromEnvironment()
        
        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "database-postgres-dev")
        #expect(config.username == "admin")
        #expect(config.password == "")
    }
    
    @Test("Database.Queue initialization with configuration")
    func testDatabaseQueueInitialization() async throws {
        let config = try Database.Configuration.fromEnvironment(connectionStrategy: .single)
        
        do {
            let queue = try await Database.Queue(configuration: config.postgresConfiguration)
            
            // Test that we can perform operations
            try await queue.write { db in
                try await db.execute("SELECT 1")
            }
            
            try await queue.close()
        } catch {
            // Print detailed error for debugging
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Database.Pool initialization with pooling")
    func testDatabasePoolInitialization() async throws {
        let config = try Database.Configuration.fromEnvironment(connectionStrategy: .pool(min: 2, max: 5))
        
        let pool = try await Database.Pool(
            configuration: config.postgresConfiguration,
            minConnections: 2,
            maxConnections: 5
        )
        
        // Test that we can perform operations
        try await pool.read { db in
            try await db.execute("SELECT 1")
        }
        
        try await pool.close()
    }
    
    @Test("Configuration passes through to PostgresQueryDatabase")
    func testConfigurationPassthrough() async throws {
        let config = Database.Configuration(
            host: "localhost",
            port: 5432,
            database: "database-postgres-dev",
            username: "admin",
            password: nil,
            connectionStrategy: .single,
            maxConnectionLifetime: 3600,
            connectionTimeout: 10
        )
        
        let pgConfig = config.postgresConfiguration
        
        #expect(pgConfig.host == "localhost")
        #expect(pgConfig.port == 5432)
        #expect(pgConfig.database == "database-postgres-dev")
        #expect(pgConfig.username == "admin")
        #expect(pgConfig.password == nil)
    }
    
    @Test("Connection strategies")
    func testConnectionStrategies() async throws {
        // Test single connection strategy
        let singleConfig = Database.Configuration(
            host: "localhost",
            port: 5432,
            database: "database-postgres-dev",
            username: "Admin",
            connectionStrategy: .single
        )
        
        let singlePgConfig = singleConfig.postgresConfiguration
        
        switch singlePgConfig.pooling {
        case .disabled:
            // Expected
            break
        case .enabled:
            Issue.record("Single connection strategy should disable pooling")
        }
        
        // Test pool connection strategy
        let poolConfig = Database.Configuration(
            host: "localhost",
            port: 5432,
            database: "database-postgres-dev",
            username: "admin",
            connectionStrategy: .pool(min: 3, max: 10)
        )
        
        let poolPgConfig = poolConfig.postgresConfiguration
        
        switch poolPgConfig.pooling {
        case .disabled:
            Issue.record("Pool connection strategy should enable pooling")
        case let .enabled(min, max):
            #expect(min == 3)
            #expect(max == 10)
        }
    }
}
