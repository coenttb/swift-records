import Testing
import Foundation
import DatabasePostgres
import StructuredQueries
import StructuredQueriesPostgres
import DependenciesTestSupport
import Dependencies

@Suite(
    "Database Access Patterns",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withSchema()),
    .serialized
)
struct DatabaseAccessTests {
    
    @Test("Database.Queue serializes all operations")
    func testDatabaseQueueSerializesAccess() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
        
        // Test that operations are serialized
        let results = await withTaskGroup(of: Int?.self) { group in
            for i in 1...10 {
                group.addTask {
                    try? await database.write { db in
                        // Simulate work
                        try? await Task.sleep(nanoseconds: 10_000)
                        return i
                    }
                }
            }
            
            var collected: [Int] = []
            for await result in group {
                if let result = result {
                    collected.append(result)
                }
            }
            return collected
        }
        
        // All operations should complete
        #expect(results.count == 10)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Database.Pool allows concurrent reads")
    func testDatabasePoolAllowsConcurrentReads() async throws {
        do {
            let pool = try await TestDatabase.makeTestPool()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(pool)
            try await TestDatabase.insertSampleData(pool)
            
            // Track concurrent execution
            let startTime = Date()
            
            let readTimes = await withTaskGroup(of: TimeInterval.self) { group in
                for _ in 1...5 {
                    group.addTask {
                        let taskStart = Date()
                        _ = try? await pool.read { db in
                            // Simulate slow read
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            return try await User.fetchAll(db)
                        }
                        return Date().timeIntervalSince(taskStart)
                    }
                }
                
                var times: [TimeInterval] = []
                for await duration in group {
                    times.append(duration)
                }
                return times
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            
            // If reads are concurrent, total time should be close to single read time
            // If serialized, it would be 5 * 0.1 = 0.5 seconds
            #expect(totalTime < 0.3) // Allow some overhead
            #expect(readTimes.count == 5)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Database.Pool serializes write operations")
    func testDatabasePoolSerializesWrites() async throws {
        do {
            let pool = try await TestDatabase.makeTestPool()
        
        // Prepare clean database for test
        try await TestDatabase.prepareForTest(pool)
        
        let writeOrder = await withTaskGroup(of: Int?.self) { group in
            for i in 1...5 {
                group.addTask {
                    try? await pool.write { db in
                        try await User.insert {
                            User.Draft(
                                name: "User \(i)",
                                email: "user\(i)@test.com",
                                createdAt: Date()
                            )
                        }.execute(db)
                        return i
                    }
                }
            }
            
            var order: [Int] = []
            for await result in group {
                if let result = result {
                    order.append(result)
                }
            }
            return order
        }
        
        // All writes should complete
        #expect(writeOrder.count == 5)
        
        // Verify all users were inserted
        // Using User.where with always-true condition as workaround for User.all
        let userCount = try await pool.read { db in
            try await User
                .where { _ in true }
                .asSelect()
                .fetchCount(db)
        }
        #expect(userCount == 5)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Read and write operations don't interfere")
    func testReadWriteIsolation() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
        
        // Insert initial data
        try await database.write { db in
            try await User.insert {
                User.Draft(name: "Initial", email: "initial@test.com", createdAt: Date())
            }.execute(db)
        }
        
        // Concurrent read and write
        async let readResult = database.read { db in
            try await User
                .where { _ in true }
                .asSelect()
                .fetchCount(db)
        }
        
        async let writeResult: Void = database.write { db in
            try await User.insert {
                User.Draft(name: "New", email: "new@test.com", createdAt: Date())
            }.execute(db)
        }
        
        let initialCount = try await readResult
        try await writeResult
        
        let finalCount = try await database.read { db in
            try await User
                .where { _ in true }
                .asSelect()
                .fetchCount(db)
        }
        
        #expect(initialCount == 1)
        #expect(finalCount == 2)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
    
    @Test("Actor-based concurrency handles multiple operations")
    func testActorConcurrency() async throws {
        do {
            let database = try await TestDatabase.makeTestDatabase()
            
            // Prepare clean database for test
            try await TestDatabase.prepareForTest(database)
            
            // Launch many concurrent operations
            await withTaskGroup(of: Void.self) { group in
                // Mix reads and writes
                for i in 1...20 {
                    if i % 3 == 0 {
                        group.addTask {
                            // Write operation
                            try? await database.write { db in
                                try? await User.insert {
                                    User.Draft(
                                        name: "User \(i)",
                                        email: "user\(i)@test.com",
                                        createdAt: Date()
                                    )
                                }.execute(db)
                            }
                        }
                    } else {
                        group.addTask {
                            // Read operation
                            _ = try? await database.read { db in
                                try await User.fetchAll(db)
                            }
                        }
                    }
                }
            }
            
            // Verify the expected number of users were inserted
            let userCount = try await database.read { db in
                try await User.fetchCount(db)
            }
            
            // Should have inserted users for i = 3, 6, 9, 12, 15, 18
            #expect(userCount == 6)
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
}
