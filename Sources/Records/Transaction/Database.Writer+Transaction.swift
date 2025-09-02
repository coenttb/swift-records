import Foundation

extension Database.Writer {
    /// Executes a block of operations within a database transaction.
    ///
    /// If the block throws an error, the transaction is rolled back.
    /// Otherwise, the transaction is committed.
    ///
    /// ```swift
    /// try await database.withTransaction { db in
    ///     try Player.insert { ... }.execute(db)
    ///     try Team.update { ... }.execute(db)
    ///     // Both operations succeed or both are rolled back
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isolation: The transaction isolation level.
    ///   - block: The operations to perform within the transaction.
    /// - Returns: The value returned by the block.
    public func withTransaction<T: Sendable>(
        isolation: TransactionIsolationLevel = .readCommitted,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await write { db in
            try await db.execute("BEGIN ISOLATION LEVEL \(isolation.rawValue)")
            do {
                let result = try await block(db)
                try await db.execute("COMMIT")
                return result
            } catch {
                try await db.execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Executes a block of operations within a database transaction and rolls it back.
    ///
    /// This is useful for testing or dry-run operations where you want to see
    /// the effects of database operations without actually committing them.
    ///
    /// ```swift
    /// let result = try await database.withRollback { db in
    ///     try Player.insert { ... }.execute(db)
    ///     return try Player.fetchCount(db)
    ///     // Transaction is rolled back, no data is persisted
    /// }
    /// ```
    ///
    /// - Parameter block: The operations to perform within the transaction.
    /// - Returns: The value returned by the block.
    public func withRollback<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await write { db in
            try await db.execute("BEGIN")
            do {
                let result = try await block(db)
                try await db.execute("ROLLBACK")
                return result
            } catch {
                try await db.execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Executes a block of operations within a savepoint.
    ///
    /// Savepoints allow you to rollback to a specific point within a transaction
    /// without rolling back the entire transaction.
    ///
    /// ```swift
    /// try await database.withTransaction { db in
    ///     try Player.insert { ... }.execute(db)
    ///     
    ///     do {
    ///         try await db.withSavepoint("risky_operation") { db in
    ///             try Team.update { ... }.execute(db)
    ///             // If this fails, only this operation is rolled back
    ///         }
    ///     } catch {
    ///         // Handle the error, but continue with the transaction
    ///     }
    ///     
    ///     try Score.insert { ... }.execute(db)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the savepoint.
    ///   - block: The operations to perform within the savepoint.
    /// - Returns: The value returned by the block.
    public func withSavepoint<T: Sendable>(
        _ name: String,
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await write { db in
            try await db.execute("SAVEPOINT \(name)")
            do {
                let result = try await block(db)
                try await db.execute("RELEASE SAVEPOINT \(name)")
                return result
            } catch {
                try await db.execute("ROLLBACK TO SAVEPOINT \(name)")
                throw error
            }
        }
    }
}
