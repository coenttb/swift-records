import Dependencies
import Foundation
@testable import Records
import RecordsTestSupport
import StructuredQueriesPostgres
import Testing

@Suite(
    "PostgresJSONB Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withSampleData())
)
struct PostgresJSONBTests {

    @Dependency(\.defaultDatabase) var db

    @Test("PostgresJSONB type alias exists")
    func testPostgresJSONBTypeAlias() {
        // Test that array types have PostgresJSONB
        let _: [String].PostgresJSONB.Type = [String].PostgresJSONB.self
        let _: [Int].PostgresJSONB.Type = [Int].PostgresJSONB.self

        // Test that dictionary types have PostgresJSONB
        let _: [String: String].PostgresJSONB.Type = [String: String].PostgresJSONB.self
        let _: [String: Int].PostgresJSONB.Type = [String: Int].PostgresJSONB.self

        #expect(true) // If we get here, the types exist
    }

    @Test("PostgresJSONB QueryBinding")
    func testPostgresJSONBBinding() {
        // Test array binding
        let arrayRep = [String].PostgresJSONB(queryOutput: ["feature1", "feature2"])
        let arrayBinding = arrayRep.queryBinding

        switch arrayBinding {
        case .jsonb(let data):
            let decoded = String(decoding: data, as: UTF8.self)
            #expect(decoded.contains("feature1"))
            #expect(decoded.contains("feature2"))
        default:
            Issue.record("Expected .jsonb binding, got \(arrayBinding)")
        }

        // Test dictionary binding
        let dictRep = [String: String].PostgresJSONB(queryOutput: ["key1": "value1", "key2": "value2"])
        let dictBinding = dictRep.queryBinding

        switch dictBinding {
        case .jsonb(let data):
            let decoded = String(decoding: data, as: UTF8.self)
            #expect(decoded.contains("key1"))
            #expect(decoded.contains("value1"))
        default:
            Issue.record("Expected .jsonb binding, got \(dictBinding)")
        }
    }

    @Test("Table with PostgresJSONB columns")
    func testTableWithPostgresJSONB() {
        // Test insert statement generation
        let insertStatement = TestTable.insert {
            TestTable(
                id: 1,
                features: ["feature1", "feature2"],
                metadata: ["key": "value"]
            )
        }

        // The statement should compile and be valid
        #expect(insertStatement != nil)
    }

    @Test("PostgresStatement handles JSONB binding")
    func testPostgresStatementJSONB() {
        // Create a query fragment with JSONB binding
        let features = ["feature1", "feature2"]
        let jsonbRep = [String].PostgresJSONB(queryOutput: features)
        let binding = jsonbRep.queryBinding

        let fragment: QueryFragment = """
            INSERT INTO test (data) VALUES (\(binding))
        """

        // Convert to PostgresStatement
        let statement = fragment.toPostgresQuery()

        // Check that the SQL is correct
        #expect(statement.sql.contains("INSERT INTO test (data) VALUES ($1)"))

        // Check that bindings were created
//        #expect(!statement.binds.cou)
    }

    @Test("Insert and retrieve JSONB data")
    func testInsertAndRetrieveJSONB() async throws {
        try await db.write { db in
            // Create the test table
            try await db.execute("""
                CREATE TABLE IF NOT EXISTS test_jsonb (
                    id INTEGER PRIMARY KEY,
                    features JSONB,
                    metadata JSONB
                )
            """)

            // Insert data with JSONB columns
            try await TestTable.insert {
                TestTable(
                    id: 1,
                    features: ["feature1", "feature2", "feature3"],
                    metadata: ["environment": "test", "version": "1.0.0"]
                )
            }.execute(db)

            // Retrieve the data
            let results = try await TestTable
                .where { $0.id == 1 }
                .fetchAll(db)

            #expect(results.count == 1)
            let record = results[0]
            #expect(record.features.count == 3)
            #expect(record.features.contains("feature1"))
            #expect(record.features.contains("feature2"))
            #expect(record.features.contains("feature3"))
            #expect(record.metadata["environment"] == "test")
            #expect(record.metadata["version"] == "1.0.0")

            // Clean up
            try await db.execute("DROP TABLE IF EXISTS test_jsonb")
        }
    }

    @Test("Update JSONB columns")
    func testUpdateJSONB() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute("""
                CREATE TABLE IF NOT EXISTS test_jsonb (
                    id INTEGER PRIMARY KEY,
                    features JSONB,
                    metadata JSONB
                )
            """)

                // Insert initial data
                try await TestTable.insert {
                    TestTable(
                        id: 2,
                        features: ["old_feature"],
                        metadata: ["status": "draft"]
                    )
                }.execute(db)

                // Update the JSONB columns
                try await TestTable
                    .where { $0.id == 2 }
                    .update {
                        $0.features = ["new_feature1", "new_feature2"]
                        $0.metadata = ["status": "published", "updated": "true"]
                    }
                    .execute(db)

                // Retrieve and verify the updated data
                let updated = try await TestTable
                    .where { $0.id == 2 }
                    .fetchOne(db)

                #expect(updated?.features.count == 2)
                #expect(updated?.features.contains("new_feature1") == true)
                #expect(updated?.features.contains("new_feature2") == true)
                #expect(updated?.metadata["status"] == "published")
                #expect(updated?.metadata["updated"] == "true")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with empty arrays and dictionaries")
    func testEmptyJSONB() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute("""
                CREATE TABLE IF NOT EXISTS test_jsonb (
                    id INTEGER PRIMARY KEY,
                    features JSONB,
                    metadata JSONB
                )
            """)

                // Insert empty arrays and dictionaries
                try await TestTable.insert {
                    TestTable(
                        id: 3,
                        features: [],
                        metadata: [:]
                    )
                }.execute(db)

                // Retrieve and verify
                let result = try await TestTable
                    .where { $0.id == 3 }
                    .fetchOne(db)

                #expect(result?.features.isEmpty == true)
                #expect(result?.metadata.isEmpty == true)

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with special characters")
    func testJSONBSpecialCharacters() async throws {
        do {
            try await db.write { db in
                // Create the test table
                try await db.execute("""
                CREATE TABLE IF NOT EXISTS test_jsonb (
                    id INTEGER PRIMARY KEY,
                    features JSONB,
                    metadata JSONB
                )
            """)

                // Insert data with special characters
                try await TestTable.insert {
                    TestTable(
                        id: 4,
                        features: ["feature\"with\"quotes", "feature'with'apostrophes", "feature\\with\\backslashes"],
                        metadata: ["key\"1": "value\"1", "key'2": "value'2", "key\\3": "value\\3"]
                    )
                }.execute(db)

                // Retrieve and verify
                let result = try await TestTable
                    .where { $0.id == 4 }
                    .fetchOne(db)

                #expect(result?.features.contains("feature\"with\"quotes") == true)
                #expect(result?.features.contains("feature'with'apostrophes") == true)
                #expect(result?.features.contains("feature\\with\\backslashes") == true)
                #expect(result?.metadata["key\"1"] == "value\"1")
                #expect(result?.metadata["key'2"] == "value'2")
                #expect(result?.metadata["key\\3"] == "value\\3")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS test_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("JSONB with optional columns")
    func testOptionalJSONB() async throws {
        do {
            try await db.write { db in
                // Create the table
                try await db.execute("""
                CREATE TABLE IF NOT EXISTS optional_jsonb (
                    id INTEGER PRIMARY KEY,
                    "optionalFeatures" JSONB,
                    "optionalMetadata" JSONB
                )
            """)

                // Insert with nil values
                try await OptionalTable.insert {
                    OptionalTable(
                        id: 1,
                        optionalFeatures: nil,
                        optionalMetadata: nil
                    )
                }.execute(db)

                // Insert with actual values
                try await OptionalTable.insert {
                    OptionalTable(
                        id: 2,
                        optionalFeatures: ["feature"],
                        optionalMetadata: ["key": "value"]
                    )
                }.execute(db)

                // Retrieve and verify
                let nilRecord = try await OptionalTable
                    .where { $0.id == 1 }
                    .fetchOne(db)

                #expect(nilRecord?.optionalFeatures == nil)
                #expect(nilRecord?.optionalMetadata == nil)

                let valueRecord = try await OptionalTable
                    .where { $0.id == 2 }
                    .fetchOne(db)

                #expect(valueRecord?.optionalFeatures?.count == 1)
                #expect(valueRecord?.optionalMetadata?["key"] == "value")

                // Clean up
                try await db.execute("DROP TABLE IF EXISTS optional_jsonb")
            }
        } catch {
            print("Detailed error: \(String(reflecting: error))")
            throw error
        }
    }
}

// Define a test table with JSONB columns
@Table("test_jsonb")
private struct TestTable {
    let id: Int
    @Column(as: [String].PostgresJSONB.self)
    let features: [String]
    @Column(as: [String: String].PostgresJSONB.self)
    let metadata: [String: String]
}

@Table("optional_jsonb")
private struct OptionalTable {
    let id: Int
    @Column(as: [String].PostgresJSONB?.self)
    let optionalFeatures: [String]?
    @Column(as: [String: String].PostgresJSONB?.self)
    let optionalMetadata: [String: String]?
}
