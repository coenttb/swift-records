import Foundation
import StructuredQueriesPostgres

// MARK: - PostgreSQL-specific Aggregate Functions

extension TableColumn {
    /// PostgreSQL STRING_AGG function - concatenates strings with a separator
    public func stringAgg(_ separator: String) -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "string_agg",
            column: queryFragment,
            separator: separator.queryFragment
        )
    }

    /// PostgreSQL ARRAY_AGG function - aggregates values into an array
    public func arrayAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "array_agg",
            column: queryFragment
        )
    }

    /// PostgreSQL JSON_AGG function - aggregates values into a JSON array
    public func jsonAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "json_agg",
            column: queryFragment
        )
    }

    /// PostgreSQL JSONB_AGG function - aggregates values into a JSONB array
    public func jsonbAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "jsonb_agg",
            column: queryFragment
        )
    }
}

// MARK: - Statistical Functions

extension TableColumn where Value: Numeric {
    /// PostgreSQL STDDEV function - standard deviation
    public func stddev() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev",
            column: queryFragment
        )
    }

    /// PostgreSQL STDDEV_POP function - population standard deviation
    public func stddevPop() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev_pop",
            column: queryFragment
        )
    }

    /// PostgreSQL STDDEV_SAMP function - sample standard deviation
    public func stddevSamp() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev_samp",
            column: queryFragment
        )
    }

    /// PostgreSQL VARIANCE function - variance
    public func variance() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "variance",
            column: queryFragment
        )
    }
}

// MARK: - Simple aggregate function helper

private struct SimpleAggregateFunction<QueryValue: QueryBindable>: QueryExpression {
    let name: String
    let column: QueryFragment
    let separator: QueryFragment?

    init(name: String, column: QueryFragment, separator: QueryFragment? = nil) {
        self.name = name
        self.column = column
        self.separator = separator
    }

    var queryFragment: QueryFragment {
        if let separator = separator {
            // For functions like string_agg that take two arguments
            return "\(QueryFragment(stringLiteral: name))(\(column), \(separator))"
        } else {
            // For single-argument aggregate functions
            return "\(QueryFragment(stringLiteral: name))(\(column))"
        }
    }
}
