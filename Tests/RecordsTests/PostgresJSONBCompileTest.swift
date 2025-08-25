import Foundation
import StructuredQueriesPostgres

// Simple compile-time test to verify PostgresJSONB types are available
struct CompileTest {
    // Test that array types have PostgresJSONB
    typealias StringArrayJSONB = [String].PostgresJSONB
    typealias IntArrayJSONB = [Int].PostgresJSONB

    // Test that dictionary types have PostgresJSONB
    typealias StringDictJSONB = [String: String].PostgresJSONB
    typealias MixedDictJSONB = [String: Int].PostgresJSONB

    // Test optional support
    typealias OptionalArrayJSONB = [String].PostgresJSONB?
    typealias OptionalDictJSONB = [String: String].PostgresJSONB?

    // Test with @Table and @Column
    @Table("test_table")
    struct TestTable {
        let id: Int

        @Column(as: [String].PostgresJSONB.self)
        let features: [String]

        @Column(as: [String: String].PostgresJSONB.self)
        let metadata: [String: String]

        @Column(as: [Int].PostgresJSONB.self)
        let numbers: [Int]

        @Column(as: [String: Int].PostgresJSONB.self)
        let counts: [String: Int]
    }
}
