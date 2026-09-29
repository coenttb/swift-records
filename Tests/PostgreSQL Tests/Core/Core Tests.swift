import Byte
import ISO_9075_Foundation
import PostgreSQL
import RFC_4122
import SQL
import SQL_Macros
import Testing
import Time

enum CoreFixtures {
    @Table("posts")
    struct Post {
        let id: Int
        var title = ""
        @Column(as: PostgreSQL.Array<String>.self)
        var tags: [String] = []
    }

    struct Settings: Codable, Equatable {
        var theme: String
        var isCompact: Bool
    }

    struct Text: QueryDecoder {
        var text: String?

        mutating func decode(_ columnType: [Byte].Type) throws(QueryDecodingError) -> [Byte]? { text.map { $0.utf8.map(Byte.init(bitPattern:)) } }
        mutating func decode(_ columnType: Double.Type) throws(QueryDecodingError) -> Double? { text.flatMap(Double.init) }
        mutating func decode(_ columnType: Int64.Type) throws(QueryDecodingError) -> Int64? { text.flatMap { Int64($0) } }
        mutating func decode(_ columnType: UInt64.Type) throws(QueryDecodingError) -> UInt64? { text.flatMap { UInt64($0) } }
        mutating func decode(_ columnType: String.Type) throws(QueryDecodingError) -> String? { text }
        mutating func decode(_ columnType: Bool.Type) throws(QueryDecodingError) -> Bool? { text.map { $0 == "t" } }
        mutating func decode(_ columnType: Int.Type) throws(QueryDecodingError) -> Int? { text.flatMap { Int($0) } }
        mutating func decode(_ columnType: Time.Instant.Type) throws(QueryDecodingError) -> Time.Instant? { nil }
        mutating func decode(_ columnType: RFC_4122.UUID.Type) throws(QueryDecodingError) -> RFC_4122.UUID? { nil }
    }
}

@Suite struct `The PostgreSQL dialect` {
    @Test func `numbers its placeholders`() {
        let rendering = PostgreSQL().render("SELECT \(ISO_9075.Value.int(1)), \(ISO_9075.Value.text("a"))")
        #expect(rendering == ISO_9075.Rendering(sql: "SELECT $1, $2", values: [.int(1), .text("a")]))
    }

    @Test func `inlines an instant as a UTC TIMESTAMPTZ`() throws {
        let instant = try Time.Instant(secondsSinceUnixEpoch: 1_767_225_600, nanosecondFraction: 250_000_000)
        #expect(try PostgreSQL().inline("\(ISO_9075.Value.timestamp(instant))") == "TIMESTAMPTZ '2026-01-01 00:00:00.250+00'")
    }

    @Test func `inlines bytes as BYTEA`() throws {
        #expect(try PostgreSQL().inline("\(ISO_9075.Value.blob([0x01, 0xAB].map(Byte.init(bitPattern:))))") == #"'\x01ab'::BYTEA"#)
    }

    @Test func `inlines array elements in the dialect`() throws {
        #expect(try PostgreSQL().inline("\(ISO_9075.Value.array([.blob([Byte(bitPattern: 0xFF)])]))") == #"ARRAY['\xff'::BYTEA]"#)
    }

    @Test func `spells an absent primary key as DEFAULT`() {
        #expect(PostgreSQL().defaultPrimaryKey == "DEFAULT")
    }

    @Test func `leaves JSON booleans to the engine`() {
        #expect(PostgreSQL().jsonBooleanOpen.isEmpty)
        #expect(PostgreSQL().jsonBooleanClose.isEmpty)
    }

    @Test func `compares with IS NOT DISTINCT FROM`() {
        let rendering = PostgreSQL().render(CoreFixtures.Post.where { $0.title.is(Optional("Taxes")) }.query)
        #expect(rendering.sql.contains(#"("posts"."title") IS NOT DISTINCT FROM ($1)"#))
        #expect(rendering.values == [.text("Taxes")])
    }

    @Test func `inserts a draft without a key as DEFAULT`() {
        let rendering = PostgreSQL().render(CoreFixtures.Post.insert { CoreFixtures.Post.Draft(title: "Hello") }.query)
        #expect(rendering.sql.hasSuffix("VALUES\n(DEFAULT, $1, '{}')"))
        #expect(rendering.values == [.text("Hello")])
    }
}

@Suite struct `Data types` {
    @Test func `name the PostgreSQL types`() {
        #expect(Int.typeName == "BIGINT")
        #expect(Int32.typeName == "INTEGER")
        #expect(Int16.typeName == "SMALLINT")
        #expect(Double.typeName == "DOUBLE PRECISION")
        #expect(Float.typeName == "REAL")
        #expect(Bool.typeName == "BOOLEAN")
        #expect(String.typeName == "TEXT")
        #expect([Byte].typeName == "BYTEA")
        #expect(Time.Instant.typeName == "TIMESTAMPTZ")
        #expect(RFC_4122.UUID.typeName == "UUID")
        #expect(Optional<Int>.typeName == "BIGINT")
    }

    @Test func `cast renders CAST AS the type name`() {
        let fragment = CoreFixtures.Post.columns.id.cast(as: String.self).queryFragment
        #expect(PostgreSQL().render(fragment).sql == #"CAST("posts"."id" AS TEXT)"#)
    }

    @Test func `an integer casts to double precision`() {
        #expect(PostgreSQL().render(CoreFixtures.Post.columns.id.cast().queryFragment).sql == #"CAST("posts"."id" AS DOUBLE PRECISION)"#)
    }
}

@Suite struct `Arrays` {
    @Test func `bind their elements as one array value`() {
        let array = PostgreSQL.Array<String>(["a", "b"])
        #expect(array.queryBinding == .array([.text("a"), .text("b")]))
        #expect(PostgreSQL().render(array.queryFragment) == ISO_9075.Rendering(sql: "$1", values: [.array([.text("a"), .text("b")])]))
    }

    @Test func `render empty as an untyped literal`() {
        #expect(PostgreSQL().render(PostgreSQL.Array<Int>([]).queryFragment) == ISO_9075.Rendering(sql: "'{}'", values: []))
    }

    @Test func `render a typed empty array`() {
        #expect(PostgreSQL().render(PostgreSQL.Array<Int>.empty().queryFragment).sql == "ARRAY[]::BIGINT[]")
    }

    @Test func `construct an array from expressions`() {
        let rendering = PostgreSQL().render(PostgreSQL.Array<Int>.of([1, 2]).queryFragment)
        #expect(rendering == ISO_9075.Rendering(sql: "ARRAY[$1, $2]", values: [.int(1), .int(2)]))
    }

    @Test func `decode the text format`() throws {
        var decoder = CoreFixtures.Text(text: #"{1,2,NULL,4}"#)
        let values = try PostgreSQL.Array<Int?>(decoder: &decoder)
        #expect(values.elements == [1, 2, nil, 4])
    }

    @Test func `decode quoted and escaped text elements`() throws {
        var decoder = CoreFixtures.Text(text: #"{plain,"with space","a \"quote\"","back\\slash",""}"#)
        let values = try PostgreSQL.Array<String>(decoder: &decoder)
        #expect(values.elements == ["plain", "with space", #"a "quote""#, #"back\slash"#, ""])
    }

    @Test func `decode booleans`() throws {
        var decoder = CoreFixtures.Text(text: "{t,f}")
        #expect(try PostgreSQL.Array<Bool>(decoder: &decoder).elements == [true, false])
    }

    @Test func `decode an empty array`() throws {
        var decoder = CoreFixtures.Text(text: "{}")
        #expect(try PostgreSQL.Array<String>(decoder: &decoder).elements == [])
    }

    @Test func `reject a multidimensional array`() {
        var decoder = CoreFixtures.Text(text: "{{1,2},{3,4}}")
        #expect(throws: QueryDecodingError.self) {
            try PostgreSQL.Array<Int>(decoder: &decoder)
        }
    }

    @Test func `reject a null element for a non-optional element type`() {
        var decoder = CoreFixtures.Text(text: "{1,NULL}")
        #expect(throws: QueryDecodingError.missingRequiredColumn) {
            try PostgreSQL.Array<Int>(decoder: &decoder)
        }
    }

    @Test func `bind as a table column`() {
        let rendering = PostgreSQL().render(
            CoreFixtures.Post.insert { CoreFixtures.Post(id: 1, title: "Hello", tags: ["swift", "sql"]) }.query
        )
        #expect(rendering.values == [.int(1), .text("Hello"), .array([.text("swift"), .text("sql")])])
    }
}

@Suite struct `JSONB` {
    @Test func `binds its value as JSON with sorted keys`() {
        let value = PostgreSQL.JSONB(queryOutput: CoreFixtures.Settings(theme: "dark", isCompact: true))
        #expect(value.queryBinding == .json(Array(#"{"isCompact":true,"theme":"dark"}"#.utf8).map(Byte.init(bitPattern:))))
    }

    @Test func `decodes its value from JSON text`() throws {
        var decoder = CoreFixtures.Text(text: #"{"theme":"light","isCompact":false}"#)
        let value = try PostgreSQL.JSONB<CoreFixtures.Settings>(decoder: &decoder)
        #expect(value.queryOutput == CoreFixtures.Settings(theme: "light", isCompact: false))
    }

    @Test func `reports malformed JSON as corrupted data`() {
        var decoder = CoreFixtures.Text(text: "{")
        #expect(throws: QueryDecodingError.self) {
            try PostgreSQL.JSONB<CoreFixtures.Settings>(decoder: &decoder)
        }
    }
}

@Suite struct `Isolation levels` {
    @Test func `begin a transaction at their level`() {
        #expect(PostgreSQL().render(PostgreSQL.Isolation.serializable.begin).sql == "BEGIN ISOLATION LEVEL SERIALIZABLE")
        #expect(PostgreSQL().render(PostgreSQL.Isolation.readCommitted.begin).sql == "BEGIN ISOLATION LEVEL READ COMMITTED")
    }
}

@Suite struct `Collations` {
    @Test func `quote their names`() {
        let fragment = CoreFixtures.Post.columns.title.collate(PostgreSQL.Collation.c).queryFragment
        #expect(PostgreSQL().render(fragment).sql == #""posts"."title" COLLATE "C""#)
    }
}
