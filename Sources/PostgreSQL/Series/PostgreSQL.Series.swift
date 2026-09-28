internal import ISO_9075_Foundation
public import SQL
public import Time

extension PostgreSQL {
    public enum Series {}
}

extension PostgreSQL.Series {
    public static func generate(
        from start: some QueryExpression<Int>,
        through stop: some QueryExpression<Int>,
        by step: (some QueryExpression<Int>)? = Int?.none
    ) -> some QueryExpression<Int> {
        SQLQueryExpression(
            "generate_series(\(([start.queryFragment, stop.queryFragment] + (step.map { [$0.queryFragment] } ?? [])).joined(separator: ", ")))",
            as: Int.self
        )
    }

    public static func generate(
        from start: some QueryExpression<Time.Instant>,
        through stop: some QueryExpression<Time.Instant>,
        every interval: String
    ) -> some QueryExpression<Time.Instant> {
        SQLQueryExpression(
            "generate_series(\(start), \(stop), \(text: interval)::interval)",
            as: Time.Instant.self
        )
    }

    public static func subscripts<Element: QueryBindable & QueryDecodable>(
        of array: some QueryExpression<PostgreSQL.Array<Element>>,
        dimension: Int = 1,
        reversed isReversed: Bool = false
    ) -> some QueryExpression<Int> {
        SQLQueryExpression(
            "generate_subscripts(\(array), \(raw: dimension)\(raw: isReversed ? ", TRUE" : ""))",
            as: Int.self
        )
    }
}
