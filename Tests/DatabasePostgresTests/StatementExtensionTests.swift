//import Testing
//import Foundation
//import DatabasePostgres
//import StructuredQueries
//import DependenciesTestSupport
//
//@Suite("Statement Extensions")
//struct StatementExtensionTests {
//    
//    @Test("Statement.execute(db) works correctly")
//    func testStatementExecute() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        
//        // Test execute with insert statement
//        try await database.write { db in
//            try await User.insert {
//                User.Draft(name: "Test User", email: "test@example.com", createdAt: Date())
//            }.execute(db)
//        }
//        
//        // Verify insertion
//        let count = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(count == 1)
//    }
//    
//    @Test("Statement.fetchAll(db) returns all results")
//    func testStatementFetchAll() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test fetchAll
//        let users = try await database.read { db in
//            try await User.all.fetchAll(db)
//        }
//        
//        #expect(users.count == 2)
//        #expect(users.contains { $0.name == "Alice" })
//        #expect(users.contains { $0.name == "Bob" })
//    }
//    
//    @Test("Statement.fetchOne(db) returns single result")
//    func testStatementFetchOne() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test fetchOne
//        let user = try await database.read { db in
//            try User
//                .where { $0.email == "alice@example.com" }
//                .fetchOne(db)
//        }
//        
//        #expect(user != nil)
//        #expect(user?.name == "Alice")
//    }
//    
//    @Test("SelectStatement.fetchCount(db) returns count")
//    func testSelectStatementFetchCount() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test fetchCount
//        let totalCount = try await database.read { db in
//            try await User.all.fetchCount(db)
//        }
//        
//        #expect(totalCount == 2)
//        
//        // Test fetchCount with filter
//        let filteredCount = try await database.read { db in
//            try await User
//                .where { $0.name == "Alice" }
//                .asSelect()
//                .fetchCount(db)
//        }
//        
//        #expect(filteredCount == 1)
//    }
//    
//    @Test("Table.all pattern works correctly")
//    func testTableAllPattern() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test the Table.all pattern from SharingGRDB
//        let allUsers = try await database.read { db in
//            try await User.all.fetchAll(db)
//        }
//        
//        let allPosts = try await database.read { db in
//            try Post.all.fetchAll(db)
//        }
//        
//        let allComments = try await database.read { db in
//            try await Comment.all.fetchAll(db)
//        }
//        
//        #expect(allUsers.count == 2)
//        #expect(allPosts.count == 2)
//        #expect(allComments.count == 1)
//    }
//    
//    @Test("Complex queries with where clauses")
//    func testComplexQueries() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test complex query with where and order
//        let publishedPosts = try await database.read { db in
//            try Post
//                .where { $0.publishedAt != nil }
//                .order(by: \.title)
//                .fetchAll(db)
//        }
//        
//        #expect(publishedPosts.count == 1)
//        #expect(publishedPosts.first?.title == "First Post")
//        
//        // Test query with multiple conditions
//        let specificUser = try await database.read { db in
//            try User
//                .where { $0.name == "Alice" && $0.email == "alice@example.com" }
//                .fetchOne(db)
//        }
//        
//        #expect(specificUser != nil)
//        #expect(specificUser?.id == 1)
//    }
//    
//    @Test("Update and delete operations")
//    func testUpdateAndDelete() async throws {
//        let database = try await TestDatabase.makeTestDatabase()
//        defer {
//            Task { try? await TestDatabase.cleanupTestTables(database) }
//        }
//        
//        try await TestDatabase.setupTestTables(database)
//        try await TestDatabase.insertSampleData(database)
//        
//        // Test update
//        try await database.write { db in
//            try User
//                .where { $0.id == 1 }
//                .update { $0.name = "Alice Updated" }
//                .execute(db)
//        }
//        
//        let updatedUser = try await database.read { db in
//            try await User.where { $0.id == 1 }.fetchOne(db)
//        }
//        
//        #expect(updatedUser?.name == "Alice Updated")
//        
//        // Test delete
//        try await database.write { db in
//            try await Comment
//                .where { $0.id == 1 }
//                .delete()
//                .execute(db)
//        }
//        
//        let commentCount = try await database.read { db in
//            try await Comment.all.fetchCount(db)
//        }
//        
//        #expect(commentCount == 0)
//    }
//}
