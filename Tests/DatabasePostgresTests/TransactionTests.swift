//import Testing
//import Foundation
//import DatabasePostgres
//import StructuredQueries
//import StructuredQueriesPostgres
//import DependenciesTestSupport
//
//@Suite(
//    "Transaction Management",
//    .dependency(\.envVars, .development),
//)
//struct TransactionTests {
//    
//    @Test("withTransaction commits on success")
//    func testWithTransaction() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Execute transaction
//        try await database.withTransaction { db in
//            try await User.insert {
//                User.Draft(name: "Transaction User", email: "tx@example.com", createdAt: Date())
//            }.execute(db)
//            
//            try await Post.insert {
//                Post.Draft(userId: 1, title: "Transaction Post", content: "Content", publishedAt: Date())
//            }.execute(db)
//        }
//        
//        // Verify both operations committed
//        let userCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        let postCount = try await database.read { db in
//            try await Post.all.fetchCount(db)
//        }
//        
//        #expect(userCount == 1)
//        #expect(postCount == 1)
//    }
//    
//    @Test("Transaction rolls back on error")
//    func testTransactionRollback() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Insert initial user
//        try await database.write { db in
//            try await User.insert {
//                User.Draft(name: "Initial", email: "initial@example.com", createdAt: Date())
//            }.execute(db)
//        }
//        
//        // Try transaction that will fail
//        do {
//            try await database.withTransaction { db in
//                // This should succeed
//                try await User.insert {
//                    User.Draft(name: "Second", email: "second@example.com", createdAt: Date())
//                }.execute(db)
//                
//                // This should fail (duplicate email)
//                try await User.insert {
//                    User.Draft(name: "Third", email: "initial@example.com", createdAt: Date())
//                }.execute(db)
//            }
//            
//            Issue.record("Transaction should have failed")
//        } catch {
//            // Expected error
//        }
//        
//        // Verify rollback - should only have initial user
//        let userCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(userCount == 1)
//    }
//    
//    @Test("Transaction isolation levels")
//    func testTransactionIsolationLevels() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Test different isolation levels
//        let isolationLevels: [TransactionIsolationLevel] = [
//            .readUncommitted,
//            .readCommitted,
//            .repeatableRead,
//            .serializable
//        ]
//        
//        for isolation in isolationLevels {
//            try await database.withTransaction(isolation: isolation) { db in
//                try await User.insert {
//                    User.Draft(
//                        name: "User \(isolation.rawValue)",
//                        email: "\(isolation.rawValue)@test.com",
//                        createdAt: Date()
//                    )
//                }.execute(db)
//            }
//        }
//        
//        let userCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(userCount == isolationLevels.count)
//    }
//    
//    @Test("withRollback always rolls back")
//    func testWithRollback() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Execute operations in rollback context
//        let result = try await database.withRollback { db in
//            try await User.insert {
//                User.Draft(name: "Rollback User", email: "rollback@example.com", createdAt: Date())
//            }.execute(db)
//            
//            // Return count within transaction
//            return try await User.all.fetchCount(db)
//        }
//        
//        // Within transaction, user was visible
//        #expect(result == 1)
//        
//        // After rollback, no users should exist
//        let finalCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(finalCount == 0)
//    }
//    
//    @Test("withSavepoint allows partial rollback")
//    func testWithSavepoint() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        try await database.withTransaction { db in
//            // Insert first user
//            try await User.insert {
//                User.Draft(name: "First", email: "first@example.com", createdAt: Date())
//            }.execute(db)
//            
//            // Try savepoint that will fail
//            do {
//                try await database.withSavepoint("risky_operation") { db in
//                    try await User.insert {
//                        User.Draft(name: "Second", email: "second@example.com", createdAt: Date())
//                    }.execute(db)
//                    
//                    // Force an error
//                    try await User.insert {
//                        User.Draft(name: "Duplicate", email: "first@example.com", createdAt: Date())
//                    }.execute(db)
//                }
//            } catch {
//                // Savepoint rolled back, but transaction continues
//            }
//            
//            // Insert third user after savepoint rollback
//            try await User.insert {
//                User.Draft(name: "Fourth", email: "fourth@example.com", createdAt: Date())
//            }.execute(db)
//        }
//        
//        // Should have first and fourth users, but not second
//        let users = try await database.read { db in
//            try await User.all.fetchAll(db)
//        }
//        
//        #expect(users.count == 2)
//        #expect(users.contains { $0.name == "First" })
//        #expect(users.contains { $0.name == "Fourth" })
//        #expect(!users.contains { $0.name == "Second" })
//    }
//    
//    @Test("Nested transactions behavior")
//    func testNestedTransactions() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Test nested transaction behavior
//        try await database.withTransaction { db in
//            try await User.insert {
//                User.Draft(name: "Outer", email: "outer@example.com", createdAt: Date())
//            }.execute(db)
//            
//            // Nested transaction (PostgreSQL doesn't support true nested transactions)
//            // This should work with savepoints internally
//            try await database.withTransaction { innerDb in
//                try await User.insert {
//                    User.Draft(name: "Inner", email: "inner@example.com", createdAt: Date())
//                }.execute(innerDb)
//            }
//        }
//        
//        let userCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(userCount == 2)
//    }
//}
