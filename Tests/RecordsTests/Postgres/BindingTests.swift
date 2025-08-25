import Foundation
import RecordsTestSupport
import Testing
//
// @Suite("Binding Tests")
// struct BindingTests {
//    @Dependency(\.defaultDatabase) var db
//    
//    @Test("UUID Bytes Binding")
//    func testBytesBinding() async throws {
//        let testDB = db
//        
//        try await testDB.execute("""
//            CREATE TABLE IF NOT EXISTS records (
//                id UUID PRIMARY KEY,
//                name TEXT,
//                duration BIGINT
//            );
//        """)
//        
//        defer {
//            Task {
//                try? await testDB.execute("DROP TABLE IF EXISTS records;")
//            }
//        }
//        
//        let record = Record(
//            id: UUID(uuidString: "deadbeef-dead-beef-dead-beefdeadbeef")!,
//            name: "Blob",
//            duration: 0
//        )
//        
//        // Test INSERT with UUID
//        let insertQuery = Record.insert { record }.returning(\.self)
//        let postgresStatement = PostgresStatement(queryFragment: insertQuery.query)
//        
//        // Verify SQL generation for PostgreSQL
//        let sql = postgresStatement.query.sql
//        #expect(sql.contains("INSERT INTO \"records\""))
//        #expect(sql.contains("($1, $2, $3)"))
//        #expect(sql.contains("RETURNING"))
//        
//        // Execute and verify
//        let results = try await testDB.execute(insertQuery)
//        #expect(results.count == 1)
//        if let inserted = results.first {
//            #expect(inserted.id == record.id)
//            #expect(inserted.name == record.name)
//            #expect(inserted.duration == record.duration)
//        }
//    }
//    
//    @Test("Integer Overflow Handling")
//    func testOverflow() async throws {
//        let testDB = db
//        
//        try await testDB.execute("""
//            CREATE TABLE IF NOT EXISTS records (
//                id UUID PRIMARY KEY,
//                name TEXT,
//                duration BIGINT
//            );
//        """)
//        
//        defer {
//            Task {
//                try? await testDB.execute("DROP TABLE IF EXISTS records;")
//            }
//        }
//        
//        // PostgreSQL BIGINT can handle UInt64.max (stored as signed)
//        // But we should test the binding behavior
//        let record = Record(
//            id: UUID(uuidString: "deadbeef-dead-beef-dead-beefdeadbeef")!,
//            name: "",
//            duration: UInt64.max
//        )
//        
//        let insertQuery = Record.insert { record }.returning(\.self)
//        
//        // This might overflow when converting to Int64 for PostgreSQL
//        // PostgreSQL BIGINT is signed, so UInt64.max won't fit
//        do {
//            _ = try await testDB.execute(insertQuery)
//            Issue.record("Expected overflow error but query succeeded")
//        } catch {
//            // Expected error for overflow
//            #expect(error.localizedDescription.contains("overflow") || 
//                   error.localizedDescription.contains("out of range"))
//        }
//    }
//    
//    @Test("UUID IN clause")
//    func testUUIDsInClause() async throws {
//        let testDB = db
//        
//        let uuid0 = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
//        let uuid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
//        let uuid2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
//        
//        let query = SimpleSelect {
//            uuid0.in([uuid1, uuid2])
//        }
//        
//        let postgresStatement = PostgresStatement(queryFragment: query.query)
//        let sql = postgresStatement.query.sql
//        
//        // PostgreSQL uses parameterized queries
//        #expect(sql.contains("SELECT"))
//        #expect(sql.contains("IN"))
//        #expect(sql.contains("$"))  // Parameters
//        
//        let results = try await testDB.execute(query)
//        #expect(results.count == 1)
//        #expect(results.first == false)
//    }
//    
//    @Test("Boolean Binding") 
//    func testBooleanBinding() async throws {
//        let testDB = db
//        
//        // Test boolean values in SELECT
//        let trueQuery = SimpleSelect { true }
//        let falseQuery = SimpleSelect { false }
//        
//        let trueResults = try await testDB.execute(trueQuery)
//        let falseResults = try await testDB.execute(falseQuery)
//        
//        #expect(trueResults.first == true)
//        #expect(falseResults.first == false)
//    }
//    
//    @Test("Date Binding")
//    func testDateBinding() async throws {
//        let testDB = db
//        
//        let testDate = Date(timeIntervalSince1970: 1234567890)
//        
//        try await testDB.execute("""
//            CREATE TABLE IF NOT EXISTS date_test (
//                id INTEGER PRIMARY KEY,
//                created_at TIMESTAMPTZ
//            );
//        """)
//        
//        defer {
//            Task {
//                try? await testDB.execute("DROP TABLE IF EXISTS date_test;")
//            }
//        }
//        
//        // Insert with date
//        let insertQuery = """
//            INSERT INTO date_test (id, created_at) VALUES ($1, $2)
//            """
//        
//        try await testDB.execute(insertQuery, bindings: [
//            .int(1),
//            .date(testDate)
//        ])
//        
//        // Query back
//        let selectQuery = "SELECT created_at FROM date_test WHERE id = $1"
//        let results = try await testDB.execute(selectQuery, bindings: [.int(1)])
//        
//        #expect(results.count == 1)
//        // Date comparison might have minor precision differences
//    }
// }
//
// @Table
// private struct Record: Equatable, Sendable {
//    // PostgreSQL has native UUID type, no need for BytesRepresentation
//    var id: UUID
//    var name = ""
//    var duration: UInt64 = 0
// }
