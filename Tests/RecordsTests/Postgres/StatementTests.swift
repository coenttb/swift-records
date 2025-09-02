// import Foundation
// import RecordsTestSupport
// import Testing
//
// @Suite("PostgresStatement Tests")
// struct StatementTests {
//    @Test("Parameter placeholder conversion")
//    func parameterPlaceholderConversion() {
//        let fragment: QueryFragment = "SELECT * FROM users WHERE id = \(1)"
//        let postgresStatement = PostgresStatement(queryFragment: fragment)
//
//        #expect(postgresStatement.query.sql == "SELECT * FROM users WHERE id = $1")
//        #expect(postgresStatement.query.binds.count == 1)
//    }
//
//    @Test("Multiple parameter conversion")
//    func multipleParameterConversion() {
//        let fragment: QueryFragment = """
//      SELECT * FROM users WHERE name = \(bind: "John") AND age > \(bind: 18)
//      """
//
//        let postgresStatement = PostgresStatement(queryFragment: fragment)
//
//        #expect(postgresStatement.query.sql.contains("$1"))
//        #expect(postgresStatement.query.sql.contains("$2"))
//        #expect(postgresStatement.query.binds.count == 2)
//    }
// }
