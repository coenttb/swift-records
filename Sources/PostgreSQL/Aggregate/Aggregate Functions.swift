internal import ISO_9075_Foundation
public import SQL

extension QueryExpression where QueryValue: QueryBindable & QueryDecodable {
    public func arrayAgg(
        distinct isDistinct: Bool = false,
        order: (some QueryExpression)? = Bool?.none,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<PostgreSQL.Array<QueryValue>?> {
        PostgreSQL.Aggregate<PostgreSQL.Array<QueryValue>?>(
            "array_agg",
            distinct: isDistinct,
            [queryFragment],
            order: order?.queryFragment,
            filter: filter?.queryFragment
        )
    }
}

extension QueryExpression where QueryValue: _OptionalPromotable<String?> {
    public func stringAgg(
        _ separator: String = ",",
        distinct isDistinct: Bool = false,
        order: (some QueryExpression)? = Bool?.none,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<String?> {
        PostgreSQL.Aggregate<String?>(
            "string_agg",
            distinct: isDistinct,
            [queryFragment, "\(bind: separator)"],
            order: order?.queryFragment,
            filter: filter?.queryFragment
        )
    }
}

extension QueryExpression where QueryValue: QueryBindable {
    @_disfavoredOverload
    public func stringAgg(
        _ separator: String = ",",
        distinct isDistinct: Bool = false,
        order: (some QueryExpression)? = Bool?.none,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<String?> {
        PostgreSQL.Aggregate<String?>(
            "string_agg",
            distinct: isDistinct,
            ["CAST(\(self) AS TEXT)", "\(bind: separator)"],
            order: order?.queryFragment,
            filter: filter?.queryFragment
        )
    }
}

extension QueryExpression
where QueryValue: _OptionalPromotable, QueryValue._Optionalized.Wrapped: Numeric {
    public func stddev(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("stddev", [queryFragment], filter: filter?.queryFragment)
    }

    public func stddevPop(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("stddev_pop", [queryFragment], filter: filter?.queryFragment)
    }

    public func stddevSamp(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("stddev_samp", [queryFragment], filter: filter?.queryFragment)
    }

    public func variance(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("variance", [queryFragment], filter: filter?.queryFragment)
    }

    public func varPop(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("var_pop", [queryFragment], filter: filter?.queryFragment)
    }

    public func varSamp(
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Double?> {
        PostgreSQL.Aggregate<Double?>("var_samp", [queryFragment], filter: filter?.queryFragment)
    }
}

extension Table {
    public static func arrayAgg<Value: QueryBindable & QueryDecodable>(
        of expression: (TableColumns) -> some QueryExpression<Value>
    ) -> Select<PostgreSQL.Array<Value>?, Self, ()> {
        select { expression($0).arrayAgg() }
    }

    public static func arrayAgg<Value: QueryBindable & QueryDecodable>(
        of expression: (TableColumns) -> some QueryExpression<Value>,
        filter: (TableColumns) -> some QueryExpression<Bool>
    ) -> Select<PostgreSQL.Array<Value>?, Self, ()> {
        select { expression($0).arrayAgg(filter: filter($0)) }
    }

    public static func stddev<Value: _OptionalPromotable>(
        of expression: (TableColumns) -> some QueryExpression<Value>
    ) -> Select<Double?, Self, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).stddev() }
    }

    public static func stddev<Value: _OptionalPromotable>(
        of expression: (TableColumns) -> some QueryExpression<Value>,
        filter: (TableColumns) -> some QueryExpression<Bool>
    ) -> Select<Double?, Self, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).stddev(filter: filter($0)) }
    }

    public static func variance<Value: _OptionalPromotable>(
        of expression: (TableColumns) -> some QueryExpression<Value>
    ) -> Select<Double?, Self, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).variance() }
    }

    public static func variance<Value: _OptionalPromotable>(
        of expression: (TableColumns) -> some QueryExpression<Value>,
        filter: (TableColumns) -> some QueryExpression<Bool>
    ) -> Select<Double?, Self, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).variance(filter: filter($0)) }
    }
}

extension Where {
    public func arrayAgg<Value: QueryBindable & QueryDecodable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>
    ) -> Select<PostgreSQL.Array<Value>?, From, ()> {
        select { expression($0).arrayAgg() }
    }

    public func arrayAgg<Value: QueryBindable & QueryDecodable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>,
        filter: (From.TableColumns) -> some QueryExpression<Bool>
    ) -> Select<PostgreSQL.Array<Value>?, From, ()> {
        select { expression($0).arrayAgg(filter: filter($0)) }
    }

    public func stddev<Value: _OptionalPromotable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>
    ) -> Select<Double?, From, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).stddev() }
    }

    public func stddev<Value: _OptionalPromotable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>,
        filter: (From.TableColumns) -> some QueryExpression<Bool>
    ) -> Select<Double?, From, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).stddev(filter: filter($0)) }
    }

    public func variance<Value: _OptionalPromotable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>
    ) -> Select<Double?, From, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).variance() }
    }

    public func variance<Value: _OptionalPromotable>(
        of expression: (From.TableColumns) -> some QueryExpression<Value>,
        filter: (From.TableColumns) -> some QueryExpression<Bool>
    ) -> Select<Double?, From, ()>
    where Value._Optionalized.Wrapped: Numeric {
        select { expression($0).variance(filter: filter($0)) }
    }
}
