import Foundation
import ResourcePool
@testable import Records

extension Database.TestDatabase: PoolableResource {
    public struct Config: Sendable {
        let setupMode: Database.TestDatabaseSetupMode
        let configuration: PostgresClient.Configuration?
        let prefix: String
        let minConnections: Int?
        let maxConnections: Int?

        public init(
            setupMode: Database.TestDatabaseSetupMode,
            configuration: PostgresClient.Configuration? = nil,
            prefix: String = "test",
            minConnections: Int? = nil,
            maxConnections: Int? = nil
        ) {
            self.setupMode = setupMode
            self.configuration = configuration
            self.prefix = prefix
            self.minConnections = minConnections
            self.maxConnections = maxConnections
        }
    }

    public static func create(config: Config) async throws -> Database.TestDatabase {
        // Create database with isolated schema
        // Use connection pool if min/max connections specified, otherwise single connection
        let database: Database.TestDatabase
        if let minConnections = config.minConnections, let maxConnections = config.maxConnections {
            database = try await Database.testDatabasePool(
                configuration: config.configuration,
                minConnections: minConnections,
                maxConnections: maxConnections,
                prefix: config.prefix
            )
        } else {
            database = try await Database.testDatabase(
                configuration: config.configuration,
                prefix: config.prefix
            )
        }

        // Setup schema based on mode
        switch config.setupMode {
        case .empty:
            break
        case .withSchema:
            try await database.createTestSchema()
        case .withSampleData:
            try await database.createTestSchema()
            try await database.insertSampleData()
        case .withReminderSchema:
            try await database.createReminderSchema()
        case .withReminderData:
            try await database.createReminderSchema()
            try await database.insertReminderSampleData()
        }

        return database
    }

    public func validate() async -> Bool {
        // Check that connection is alive
        do {
            try await self.read { db in
                try await db.execute("SELECT 1")
            }
            return true
        } catch {
            return false
        }
    }

    public func reset() async throws {
        // For test databases, validation is enough
        // We don't need to clean tables since each test uses isolated schemas
        // But we could add table truncation here if needed for shared-schema tests
    }
}
