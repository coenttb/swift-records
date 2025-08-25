//
//  File.swift
//  swift-records
//
//  Created by Coen ten Thije Boonkkamp on 31/08/2025.
//

import Foundation
import StructuredQueriesPostgres

extension QueryExpression where QueryValue: QueryBindable {
    /// A count aggregate of this expression.
    ///
    /// Counts the number of non-`NULL` times the expression appears in a group.
    ///
    /// ```swift
    /// Reminder.select { $0.id.count() }
    /// // SELECT count("reminders"."id") FROM "reminders"
    ///
    /// Reminder.select { $0.title.count(distinct: true) }
    /// // SELECT count(DISTINCT "reminders"."title") FROM "reminders"
    /// ```
    ///
    /// - Parameters:
    ///   - isDistinct: Whether or not to include a `DISTINCT` clause, which filters duplicates from
    ///     the aggregation.
    ///   - filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A count aggregate of this expression.
    public func count(
        distinct isDistinct: Bool = false,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Int> {
        AggregateFunction(
            "count",
            isDistinct: isDistinct,
            [queryFragment],
            filter: filter?.queryFragment
        )
    }
}

// SQLite group_concat removed - use PostgreSQL's string_agg() instead (available in PostgreSQLFunctions.swift)

extension QueryExpression where QueryValue: QueryBindable & _OptionalPromotable {
    /// A maximum aggregate of this expression.
    ///
    /// ```swift
    /// Reminder.select { $0.date.max() }
    /// // SELECT max("reminders"."date") FROM "reminders"
    /// ```
    ///
    /// - Parameters filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A maximum aggregate of this expression.
    public func max(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<QueryValue._Optionalized.Wrapped?> {
        AggregateFunction("max", [queryFragment], filter: filter?.queryFragment)
    }

    /// A minimum aggregate of this expression.
    ///
    /// ```swift
    /// Reminder.select { $0.date.max() }
    /// // SELECT min("reminders"."date") FROM "reminders"
    /// ```
    ///
    /// - Parameters filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A minimum aggregate of this expression.
    public func min(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<QueryValue._Optionalized.Wrapped?> {
        AggregateFunction("min", [queryFragment], filter: filter?.queryFragment)
    }
}

extension QueryExpression
where QueryValue: _OptionalPromotable, QueryValue._Optionalized.Wrapped: Numeric {
    /// An average aggregate of this expression.
    ///
    /// ```swift
    /// Reminder.select { $0.date.max() }
    /// // SELECT min("reminders"."date") FROM "reminders"
    /// ```
    ///
    /// - Parameters:
    ///   - isDistinct: Whether or not to include a `DISTINCT` clause, which filters duplicates from
    ///     the aggregation.
    ///   - filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: An average aggregate of this expression.
    public func avg(
        distinct isDistinct: Bool = false,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        AggregateFunction("avg", isDistinct: isDistinct, [queryFragment], filter: filter?.queryFragment)
    }

    /// An sum aggregate of this expression.
    ///
    /// ```swift
    /// Item.select { $0.quantity.sum() }
    /// // SELECT sum("items"."quantity") FROM "items"
    /// ```
    ///
    /// - Parameters:
    ///   - isDistinct: Whether or not to include a `DISTINCT` clause, which filters duplicates from
    ///     the aggregation.
    ///   - filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A sum aggregate of this expression.
    public func sum(
        distinct isDistinct: Bool = false,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> SQLQueryExpression<QueryValue._Optionalized> {
        // NB: We must explicitly erase here to avoid a runtime crash with opaque return types
        // TODO: Report issue to Swift team.
        SQLQueryExpression(
            AggregateFunction<QueryValue._Optionalized>(
                "sum",
                isDistinct: isDistinct,
                [queryFragment],
                filter: filter?.queryFragment
            )
            .queryFragment
        )
    }

    // SQLite total removed - use PostgreSQL's COALESCE(SUM(...), 0) or sumOrZero() instead
}

extension QueryExpression where Self == AggregateFunction<Int> {
    /// A `count(*)` aggregate.
    ///
    /// ```swift
    /// Reminder.select { .count() }
    /// // SELECT count(*) FROM "reminders"
    /// ```
    ///
    /// - Parameter filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A `count(*)` aggregate.
    public static func count(
        filter: (any QueryExpression<Bool>)? = nil
    ) -> Self {
        AggregateFunction("count", ["*"], filter: filter?.queryFragment)
    }
}

/// A query expression of an aggregate function.
public struct AggregateFunction<QueryValue>: QueryExpression, Sendable {
    var name: QueryFragment
    var isDistinct: Bool
    var arguments: [QueryFragment]
    var order: QueryFragment?
    var filter: QueryFragment?

    init(
        _ name: QueryFragment,
        isDistinct: Bool = false,
        _ arguments: [QueryFragment] = [],
        order: QueryFragment? = nil,
        filter: QueryFragment? = nil
    ) {
        self.name = name
        self.isDistinct = isDistinct
        self.arguments = arguments
        self.order = order
        self.filter = filter
    }

    public var queryFragment: QueryFragment {
        var query: QueryFragment = "\(name)("
        if isDistinct {
            query.append("DISTINCT ")
        }
        query.append(arguments.joined(separator: ", "))
        if let order {
            query.append(" ORDER BY \(order)")
        }
        query.append(")")
        if let filter {
            query.append(" FILTER (WHERE \(filter))")
        }
        return query
    }
}

extension QueryExpression where QueryValue == String {
    /// A predicate expression from this string expression matched against another _via_ the `ILIKE`
    /// operator (case-insensitive LIKE in PostgreSQL).
    ///
    /// ```swift
    /// Reminder.where { $0.title.ilike("%GET%") }
    /// // SELECT … FROM "reminders" WHERE ("reminders"."title" ILIKE '%GET%')
    /// ```
    ///
    /// - Parameters:
    ///   - pattern: A string expression describing the `ILIKE` pattern.
    ///   - escape: An optional character for the `ESCAPE` clause.
    /// - Returns: A predicate expression.
    public func ilike(
        _ pattern: some StringProtocol,
        escape: Character? = nil
    ) -> some QueryExpression<Bool> {
        IlikeOperator(string: self, pattern: "\(pattern)", escape: escape)
    }
}

private struct IlikeOperator<
    LHS: QueryExpression<String>,
    RHS: QueryExpression<String>
>: QueryExpression {
    typealias QueryValue = Bool

    let string: LHS
    let pattern: RHS
    let escape: Character?

    var queryFragment: QueryFragment {
        var query: QueryFragment = "(\(string.queryFragment) ILIKE \(pattern.queryFragment)"
        if let escape {
            query.append(" ESCAPE \(bind: String(escape))")
        }
        query.append(")")
        return query
    }
}

extension QueryExpression where QueryValue: Collection {
    /// Wraps this expression with the `length` function.
    ///
    /// ```swift
    /// Reminder.select { $0.title.length() }
    /// // SELECT length("reminders"."title") FROM "reminders"
    ///
    /// Asset.select { $0.bytes.length() }
    /// // SELECT length("assets"."bytes") FROM "assets
    /// ```
    ///
    /// - Returns: An integer expression of the `length` function wrapping this expression.
    public func length() -> some QueryExpression<Int> {
        QueryFunction("length", self)
    }
}

extension QueryExpression where QueryValue: FloatingPoint {
    /// Wraps this floating point query expression with the `round` function.
    ///
    /// ```swift
    /// Item.select { $0.price.round() }
    /// // SELECT round("items"."price") FROM "items"
    ///
    /// Item.select { $0.price.avg().round(2) }
    /// // SELECT round(avg("items"."price"), 2) FROM "items"
    /// ```
    ///
    /// - Parameter precision: The number of digits to the right of the decimal point to round to.
    /// - Returns: An expression wrapped with the `round` function.
    public func round(
        _ precision: (some QueryExpression<Int>)? = Int?.none
    ) -> some QueryExpression<QueryValue> {
        if let precision {
            return QueryFunction("round", self, precision)
        } else {
            return QueryFunction("round", self)
        }
    }
}

extension QueryExpression
where QueryValue: _OptionalPromotable, QueryValue._Optionalized.Wrapped: Numeric {
    /// Wraps this numeric query expression with the `abs` function.
    ///
    /// - Returns: An expression wrapped with the `abs` function.
    public func abs() -> some QueryExpression<QueryValue> {
        QueryFunction("abs", self)
    }

    /// Wraps this numeric query expression with the `sign` function.
    ///
    /// - Returns: An expression wrapped with the `sign` function.
    public func sign() -> some QueryExpression<QueryValue> {
        QueryFunction("sign", self)
    }
}

// SQLite ifnull removed - use PostgreSQL's coalesce() instead (already available via ?? operator)

extension QueryExpression where QueryValue: _OptionalProtocol {
    /// Applies each side of the operator to the `coalesce` function
    ///
    /// ```swift
    /// Reminder.select { $0.date ?? #sql("date()") }
    /// // SELECT coalesce("reminders"."date", date()) FROM "reminders"
    /// ```
    ///
    /// > Tip: Heavily overloaded Swift operators can tax the compiler. You can use ``coalesce(_:)``,
    /// > instead, if you find a particular query builds slowly. See
    /// > <doc:CompilerPerformance#Method-operators> for more information.
    ///
    /// - Parameters:
    ///   - lhs: An optional query expression.
    ///   - rhs: A non-optional query expression
    /// - Returns: A non-optional query expression of the `coalesce` function wrapping both arguments.
    public static func ?? (
        lhs: Self,
        rhs: some QueryExpression<QueryValue.Wrapped>
    ) -> CoalesceFunction<QueryValue.Wrapped> {
        CoalesceFunction([lhs.queryFragment, rhs.queryFragment])
    }

    /// Applies each side of the operator to the `coalesce` function
    ///
    /// ```swift
    /// Reminder.select { $0.date ?? #sql("date()") }
    /// // SELECT coalesce("reminders"."date", date()) FROM "reminders"
    /// ```
    ///
    /// > Tip: Heavily overloaded Swift operators can tax the compiler. You can use ``coalesce(_:)``,
    /// > instead, if you find a particular query builds slowly. See
    /// > <doc:CompilerPerformance#Method-operators> for more information.
    ///
    /// - Parameters:
    ///   - lhs: An optional query expression.
    ///   - rhs: Another optional query expression
    /// - Returns: An optional query expression of the `coalesce` function wrapping both arguments.
    public static func ?? (
        lhs: Self,
        rhs: some QueryExpression<QueryValue>
    ) -> CoalesceFunction<QueryValue> {
        CoalesceFunction([lhs.queryFragment, rhs.queryFragment])
    }

    @_documentation(visibility: private)
    @available(
        *,
         deprecated,
         message:
            "Left side of 'NULL' coalescing operator '??' has non-optional query type, so the right side is never used"
    )
    public static func ?? (
        lhs: some QueryExpression<QueryValue.Wrapped>,
        rhs: Self
    ) -> CoalesceFunction<QueryValue> {
        CoalesceFunction([lhs.queryFragment, rhs.queryFragment])
    }
}

extension QueryExpression {
    @_documentation(visibility: private)
    @available(
        *,
         deprecated,
         message:
            "Left side of 'NULL' coalescing operator '??' has non-optional query type, so the right side is never used"
    )
    public static func ?? (
        lhs: some QueryExpression<QueryValue>,
        rhs: Self
    ) -> CoalesceFunction<QueryValue> {
        CoalesceFunction([lhs.queryFragment, rhs.queryFragment])
    }
}

// SQLite instr removed - use PostgreSQL's position() or strpos() instead

extension QueryExpression where QueryValue: _OptionalPromotable<String?> {
    /// Wraps this string expression with the `lower` function.
    ///
    /// - Returns: An expression wrapped with the `lower` function.
    public func lower() -> some QueryExpression<QueryValue> {
        QueryFunction("lower", self)
    }
}

extension QueryExpression where QueryValue == String {
    /// Wraps this string expression with the `ltrim` function.
    ///
    /// - Parameter characters: Characters to trim.
    /// - Returns: An expression wrapped with the `ltrim` function.
    public func ltrim(
        _ characters: (some QueryExpression<QueryValue>)? = QueryValue?.none
    ) -> some QueryExpression<QueryValue> {
        if let characters {
            return QueryFunction("ltrim", self, characters)
        } else {
            return QueryFunction("ltrim", self)
        }
    }

    /// Creates an expression invoking the `octet_length` function with the given string expression.
    ///
    /// - Returns: An integer expression of the `octet_length` function wrapping the given string.
    public func octetLength() -> some QueryExpression<Int> {
        QueryFunction("octet_length", self)
    }
}

// SQLite quote removed - use PostgreSQL's quote_literal() or quote_ident() instead

extension QueryExpression where QueryValue == String {
    /// Creates an expression invoking the `replace` function.
    ///
    /// - Parameters:
    ///   - other: The substring to be replaced.
    ///   - replacement: The replacement string.
    /// - Returns: An expression of the `replace` function wrapping the given string, a substring to
    ///   replace, and the replacement.
    public func replace(
        _ other: some QueryExpression<QueryValue>,
        _ replacement: some QueryExpression<QueryValue>
    ) -> some QueryExpression<QueryValue> {
        QueryFunction("replace", self, other, replacement)
    }

    /// Wraps this string expression with the `rtrim` function.
    ///
    /// - Parameter characters: Characters to trim.
    /// - Returns: An expression wrapped with the `rtrim` function.
    public func rtrim(
        _ characters: (some QueryExpression<QueryValue>)? = QueryValue?.none
    ) -> some QueryExpression<QueryValue> {
        if let characters {
            return QueryFunction("rtrim", self, characters)
        } else {
            return QueryFunction("rtrim", self)
        }
    }

    /// Creates an expression invoking the `substr` function.
    ///
    /// - Parameters:
    ///   - offset: The substring to be replaced.
    ///   - length: The replacement string.
    /// - Returns: An expression of the `substr` function wrapping the given string, an offset, and
    ///   length.
    public func substr(
        _ offset: some QueryExpression<Int>,
        _ length: (some QueryExpression<Int>)? = Int?.none
    ) -> some QueryExpression<QueryValue> {
        if let length {
            return QueryFunction("substr", self, offset, length)
        } else {
            return QueryFunction("substr", self, offset)
        }
    }

    /// Wraps this string expression with the `trim` function.
    ///
    /// - Parameter characters: Characters to trim.
    /// - Returns: An expression wrapped with the `trim` function.
    public func trim(
        _ characters: (some QueryExpression<QueryValue>)? = QueryValue?.none
    ) -> some QueryExpression<QueryValue> {
        if let characters {
            return QueryFunction("trim", self, characters)
        } else {
            return QueryFunction("trim", self)
        }
    }

    // SQLite unhex and unicode removed - use PostgreSQL's decode(string, 'hex') and ascii() instead

    /// Wraps this string expression with the `upper` function.
    ///
    /// - Returns: An expression wrapped with the `upper` function.
    public func upper() -> some QueryExpression<QueryValue> {
        QueryFunction("upper", self)
    }
}

// SQLite hex removed - use PostgreSQL's encode(data, 'hex') instead

public struct QueryFunction<QueryValue>: QueryExpression {
    let name: QueryFragment
    let arguments: [QueryFragment]

    public init<each Argument: QueryExpression>(_ name: QueryFragment, _ arguments: repeat each Argument) {
        self.name = name
        self.arguments = Array(repeat each arguments)
    }

    public var queryFragment: QueryFragment {
        "\(name)(\(arguments.joined(separator: ", ")))"
    }
}

/// A query expression of a coalesce function.
public struct CoalesceFunction<QueryValue>: QueryExpression {
    private let arguments: [QueryFragment]

    fileprivate init(_ arguments: [QueryFragment]) {
        self.arguments = arguments
    }

    public var queryFragment: QueryFragment {
        "coalesce(\(arguments.joined(separator: ", ")))"
    }

    public static func ?? <T: _OptionalProtocol<QueryValue>>(
        lhs: some QueryExpression<T>,
        rhs: Self
    ) -> CoalesceFunction<QueryValue> {
        Self([lhs.queryFragment] + rhs.arguments)
    }
}

extension CoalesceFunction where QueryValue: _OptionalProtocol {
    public static func ?? (
        lhs: some QueryExpression<QueryValue>,
        rhs: Self
    ) -> Self {
        Self([lhs.queryFragment] + rhs.arguments)
    }
}
