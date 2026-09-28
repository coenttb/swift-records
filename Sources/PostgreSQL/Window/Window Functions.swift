internal import ISO_9075_Foundation
public import SQL

extension QueryExpression where QueryValue: QueryBindable {
    public func lag(
        offset: Int = 1,
        default defaultValue: QueryValue? = nil
    ) -> PostgreSQL.Window.Function<QueryValue._Optionalized> {
        PostgreSQL.Window.Function(
            "LAG",
            [queryFragment, "\(raw: offset)"] + (defaultValue.map { [$0.queryFragment] } ?? [])
        )
    }

    public func lead(
        offset: Int = 1,
        default defaultValue: QueryValue? = nil
    ) -> PostgreSQL.Window.Function<QueryValue._Optionalized> {
        PostgreSQL.Window.Function(
            "LEAD",
            [queryFragment, "\(raw: offset)"] + (defaultValue.map { [$0.queryFragment] } ?? [])
        )
    }

    public func firstValue() -> PostgreSQL.Window.Function<QueryValue> {
        PostgreSQL.Window.Function("FIRST_VALUE", [queryFragment])
    }

    public func lastValue() -> PostgreSQL.Window.Function<QueryValue> {
        PostgreSQL.Window.Function("LAST_VALUE", [queryFragment])
    }

    public func nthValue(_ position: Int) -> PostgreSQL.Window.Function<QueryValue._Optionalized> {
        precondition(position > 0, "nth value position must be positive (1-indexed)")
        return PostgreSQL.Window.Function("NTH_VALUE", [queryFragment, "\(raw: position)"])
    }
}
