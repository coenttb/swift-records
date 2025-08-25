import Testing
import Foundation
import DatabasePostgres
import StructuredQueries
import StructuredQueriesPostgres
import DependenciesTestSupport
import Dependencies

@Suite(
    "Statement Extensions",
    .dependency(\.envVars, .development),
    .serialized
)
struct StatementExtensionTests {
    
    @Test("Statement.execute(db) works correctly")
    func testStatementExecute() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            
            // Test execute with insert statement
            try await database.write { db in
                try await User.insert {
                    User.Draft(name: "Test User", email: "test@example.com", createdAt: Date())
                }.execute(db)
            }
            
            // Verify insertion
            let count = try await database.read { db in
                try await User
                    .where { _ in true }
                    .asSelect()
                    .fetchCount(db)
            }
            
            #expect(count == 1)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Statement.fetchAll(db) returns all results")
    func testStatementFetchAll() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test fetchAll using static method
            let users = try await database.read { db in
                try await User.fetchAll(db)
            }
            
            #expect(users.count == 2)
            #expect(users.contains { $0.name == "Alice" })
            #expect(users.contains { $0.name == "Bob" })
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Statement.fetchOne(db) returns single result")
    func testStatementFetchOne() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test fetchOne
            let user = try await database.read { db in
                try await User
                    .where { $0.email == "alice@example.com" }
                    .asSelect()
                    .fetchOne(db)
            }
            
            #expect(user != nil)
            #expect(user?.name == "Alice")
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("SelectStatement.fetchCount(db) returns count")
    func testSelectStatementFetchCount() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test fetchCount using static method
            let totalCount = try await database.read { db in
                try await User.fetchCount(db)
            }
            
            #expect(totalCount == 2)
            
            // Test fetchCount with filter
            let filteredCount = try await database.read { db in
                try await User
                    .where { $0.name == "Alice" }
                    .asSelect()
                    .fetchCount(db)
            }
            
            #expect(filteredCount == 1)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Table.all pattern works correctly")
    func testTableAllPattern() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test the Table.all pattern from SharingGRDB
            let allUsers = try await database.read { db in
                try await User.all.fetchAll(db)
            }
            
            let allPosts = try await database.read { db in
                try await Post.all.fetchAll(db)
            }
            
            let allComments = try await database.read { db in
                try await Comment.all.fetchAll(db)
            }
            
            #expect(allUsers.count == 2)
            #expect(allPosts.count == 2)
            #expect(allComments.count == 1)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Complex queries with where clauses")
    func testComplexQueries() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test complex query with where and order
            let publishedPosts = try await database.read { db in
                try await Post
                    .where { $0.publishedAt != nil }
                    .order(by: \.title)
                    .asSelect()
                    .fetchAll(db)
            }
            
            #expect(publishedPosts.count == 1)
            #expect(publishedPosts.first?.title == "First Post")
            
            // Test query with multiple conditions
            let specificUser = try await database.read { db in
                try await User
                    .where { $0.name == "Alice" && $0.email == "alice@example.com" }
                    .asSelect()
                    .fetchOne(db)
            }
            
            #expect(specificUser != nil)
            #expect(specificUser?.id == 1)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Update and delete operations")
    func testUpdateAndDelete() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            try await TestDatabase.insertSampleData(database)
            
            // Test update
            try await database.write { db in
                try await User
                    .where { $0.id == 1 }
                    .update { $0.name = "Alice Updated" }
                    .execute(db)
            }
            
            let updatedUser = try await database.read { db in
                try await User
                    .where { $0.id == 1 }
                    .asSelect()
                    .fetchOne(db)
            }
            
            #expect(updatedUser?.name == "Alice Updated")
            
            // Test delete
            try await database.write { db in
                try await Comment
                    .where { $0.id == 1 }
                    .delete()
                    .execute(db)
            }
            
            let commentCount = try await database.read { db in
                try await Comment
                    .where { _ in true }
                    .asSelect()
                    .fetchCount(db)
            }
            
            #expect(commentCount == 0)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
}