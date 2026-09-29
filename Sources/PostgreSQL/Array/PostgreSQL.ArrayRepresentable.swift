public import SQL

extension PostgreSQL {
    public protocol ArrayRepresentable: QueryBindable {
        associatedtype Element: QueryBindable & QueryDecodable
    }
}

extension PostgreSQL.Array: PostgreSQL.ArrayRepresentable {}

extension Optional: PostgreSQL.ArrayRepresentable where Wrapped: PostgreSQL.ArrayRepresentable {
    public typealias Element = Wrapped.Element
}
