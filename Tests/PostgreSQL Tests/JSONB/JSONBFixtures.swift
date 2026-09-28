import Byte
import PostgreSQL
import SQL
import SQL_Macros

enum JSONBFixtures {
    @Table("users")
    struct User {
        let id: Int
        var name: String
        var settings: [Byte]
        var preferences: [Byte]?
        @Column(as: PostgreSQL.JSONB<[String: String]>.self)
        var metadata: [String: String]
        @Column(as: PostgreSQL.Array<String>.self)
        var tags: [String]
    }

    @Table("orders")
    struct Order {
        let id: Int
        var isPaid: Bool
        var amount: Double
    }

    static let reservedPath = ["a,b", "o'brien", "}"]

    static let escapePath = [#"a"b"#, #"c\d"#]

    static func queryValue<Value>(of _: some QueryExpression<Value>) -> Value.Type {
        Value.self
    }
}
