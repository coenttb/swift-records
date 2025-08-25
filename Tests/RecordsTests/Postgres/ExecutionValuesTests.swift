// import Foundation
// import RecordsTestSupport
// import Testing
//
// @Suite(
//    "VALUES Execution Tests"
// )
// struct ExecutionValuesTests {
//    let db: TestDatabase
//    
//    init() async throws {
//        // Create database with schema only (no sample data needed)
//        self.db = try await TestDatabase.create(withSampleData: false)
//    }
//    
//    deinit {
//        Task { await db.cleanup() }
//    }
//    
//    @Test("VALUES basic execution")
//    func valuesBasic() async throws {
//        do {
//            let results = try await db.execute(Values(1, "Hello", true))
//            
//            #expect(results.count == 1)
//            let first = results.first!
//            #expect(first.0 == 1)
//            #expect(first.1 == "Hello")
//            #expect(first.2 == true)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
//    
//    @Test("VALUES with UNION")
//    func valuesUnion() async throws {
//        do {
//            let results = try await db.execute(
//                Values(1, "Hello", true)
//                    .union(Values(2, "Goodbye", false))
//            )
//            
//            #expect(results.count == 2)
//            
//            let first = results[0]
//            #expect(first.0 == 1)
//            #expect(first.1 == "Hello")
//            #expect(first.2 == true)
//            
//            let second = results[1]
//            #expect(second.0 == 2)
//            #expect(second.1 == "Goodbye")
//            #expect(second.2 == false)
//        } catch {
//            print("Detailed error: \(String(reflecting: error))")
//            throw error
//        }
//    }
// }
