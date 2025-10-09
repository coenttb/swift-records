import Dependencies
import DependenciesTestSupport
import Foundation
import RecordsTestSupport
import Testing

@Suite(
    "Transaction Management",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withSchema()
    }
)
struct TransactionTests {
    @Dependency(\.defaultDatabase) var database

    @Test("withTransaction commits on success")
    func testWithTransaction() async throws {
        // Execute transaction
        try await database.withTransaction { db in
            try await User.insert {
                User.Draft(name: "Transaction User", email: "tx@example.com", createdAt: Date())
            }.execute(db)

            try await Post.insert {
                Post.Draft(userId: 1, title: "Transaction Post", content: "Content", publishedAt: Date())
            }.execute(db)
        }

        // Verify data was committed
        let userCount = try await database.read { db in
            try await User.fetchCount(db)
        }

        let postCount = try await database.read { db in
            try await Post.fetchCount(db)
        }

        #expect(userCount == 1)
        #expect(postCount == 1)
    }

    @Test("Transaction rolls back on error")
    func testTransactionRollback() async throws {
        // Count initial state
        let initialUserCount = try await database.read { db in
            try await User.fetchCount(db)
        }

        // Attempt transaction that will fail
        do {
            try await database.withTransaction { db in
                // This should succeed
                try await User.insert {
                    User.Draft(name: "Will Rollback", email: "rollback@example.com", createdAt: Date())
                }.execute(db)

                // Force an error
                struct TestError: Error {}
                throw TestError()
            }

            Issue.record("Transaction should have failed")
        } catch {
            // Expected error
        }

        // Verify rollback
        let finalUserCount = try await database.read { db in
            try await User.fetchCount(db)
        }

        #expect(finalUserCount == initialUserCount)
    }

    @Test("Transaction isolation levels")
    func testTransactionIsolationLevels() async throws {
        // Test different isolation levels
        let isolationLevels: [TransactionIsolationLevel] = [
            .readCommitted,
            .repeatableRead,
            .serializable
        ]

        for level in isolationLevels {
            try await database.withTransaction(isolation: level) { db in
                try await User.insert {
                    User.Draft(
                        name: "Isolation \(level)",
                        email: "iso-\(level)@example.com",
                        createdAt: Date()
                    )
                }.execute(db)
            }
        }

        // Verify all were inserted
        let users = try await database.read { db in
            try await User.fetchAll(db)
        }

        #expect(users.count >= 3)
    }

    @Test("withRollback always rolls back")
    func testWithRollback() async throws {
        // Count initial state
        let initialCount = try await database.read { db in
            try await User.fetchCount(db)
        }

        // Execute with rollback
        try await database.withRollback { db in
            try await User.insert {
                User.Draft(name: "Will Rollback", email: "rollback2@example.com", createdAt: Date())
            }.execute(db)

            // Verify insert worked within transaction
            let count = try await User.fetchCount(db)
            #expect(count == initialCount + 1)
        }

        // Verify rollback occurred
        let finalCount = try await database.read { db in
            try await User.fetchCount(db)
        }

        #expect(finalCount == initialCount)
    }

    @Test(
        "withSavepoint allows partial rollback",
        .disabled()
    )
    func testWithSavepoint() async throws {
        try await database.withTransaction { db in
            // Insert first user
            try await User.insert {
                User.Draft(name: "Before Savepoint", email: "before@example.com", createdAt: Date())
            }.execute(db)

            // Try savepoint that will rollback
            do {
                try await database.withSavepoint("test_savepoint") { spDb in
                    try await User.insert {
                        User.Draft(name: "In Savepoint", email: "savepoint@example.com", createdAt: Date())
                    }.execute(spDb)

                    // Force rollback of savepoint
                    struct SavepointError: Error {}
                    throw SavepointError()
                }
            } catch {
                // Expected - savepoint rolled back
            }

            // Insert after savepoint
            try await User.insert {
                User.Draft(name: "After Savepoint", email: "after@example.com", createdAt: Date())
            }.execute(db)
        }

        // Verify only users outside savepoint were committed
        let users = try await database.read { db in
            try await User.fetchAll(db)
        }

        let names = users.map(\.name)
        #expect(names.contains("Before Savepoint"))
        #expect(names.contains("After Savepoint"))
        #expect(!names.contains("In Savepoint"))
    }

    @Test(
        "Nested transactions behavior",
        .disabled()
    )
    func testNestedTransactions() async throws {
        // Test nested transaction behavior
        try await database.withTransaction { db1 in
            try await User.insert {
                User.Draft(name: "Outer Transaction", email: "outer@example.com", createdAt: Date())
            }.execute(db1)

            // Nested transaction (actually a savepoint in PostgreSQL)
            try await database.withTransaction { db2 in
                try await User.insert {
                    User.Draft(name: "Inner Transaction", email: "inner@example.com", createdAt: Date())
                }.execute(db2)
            }
        }

        // Both should be committed
        let users = try await database.read { db in
            try await User.fetchAll(db)
        }

        let names = users.map(\.name)
        #expect(names.contains("Outer Transaction"))
        #expect(names.contains("Inner Transaction"))
    }
}
