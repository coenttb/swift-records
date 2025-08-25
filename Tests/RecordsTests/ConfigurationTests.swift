import Testing
import Foundation
@testable import Records
import Dependencies
import EnvironmentVariables
import DependenciesTestSupport

@Suite(
    "Configuration",
    .dependency(\.envVars, .development)
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
            let queue = try await Database.Queue(configuration: config)
            
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
        let config = try Database.Configuration.fromEnvironment(connectionStrategy: .pool(min: 2, max: 5))
        
        let pool = try await Database.Pool(
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
        
        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "database-postgres-dev")
        #expect(config.username == "admin")
        #expect(config.password == nil)
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
        
        switch singleConfig.connectionStrategy {
        case .single:
            // Expected
            break
        case .pool:
            Issue.record("Expected single connection strategy")
        }
        
        // Test pool connection strategy
        let poolConfig = Database.Configuration(
            host: "localhost",
            port: 5432,
            database: "database-postgres-dev",
            username: "admin",
            connectionStrategy: .pool(min: 3, max: 10)
        )
        
        switch poolConfig.connectionStrategy {
        case .single:
            Issue.record("Expected pool connection strategy")
        case let .pool(min, max):
            #expect(min == 3)
            #expect(max == 10)
        }
    }
}
