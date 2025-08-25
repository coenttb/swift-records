import Foundation
import StructuredQueries

// MARK: - DatabaseMigration Table

/// Internal table for tracking applied database migrations.
///
/// This table is used by `Database.Migrator` to track which migrations
/// have been applied to the database.
@Table("__database_migrations")
struct DatabaseMigration {
    /// The unique identifier for the migration
    let identifier: String
    
    /// When the migration was applied
    let appliedAt: Date
    
    /// Create a new migration record
    init(identifier: String, appliedAt: Date = Date()) {
        self.identifier = identifier
        self.appliedAt = appliedAt
    }
}

// MARK: - Helper Extensions

extension DatabaseMigration {
    /// Fetch all applied migration identifiers
    static func fetchAppliedIdentifiers(_ db: any Database.Connection.`Protocol`) async throws -> Set<String> {
        let migrations = try await DatabaseMigration.fetchAll(db)
        return Set(migrations.map { $0.identifier })
    }
    
    /// Record a migration as applied
    static func recordMigration(identifier: String, db: any Database.Connection.`Protocol`) async throws {
        try await DatabaseMigration.insert {
            DatabaseMigration(identifier: identifier)
        }.execute(db)
    }
    
    /// Check if a specific migration has been applied
    static func hasApplied(identifier: String, db: any Database.Connection.`Protocol`) async throws -> Bool {
        let migration = try await DatabaseMigration
            .where { $0.identifier == identifier }
            .fetchOne(db)
        
        return migration != nil
    }
}
