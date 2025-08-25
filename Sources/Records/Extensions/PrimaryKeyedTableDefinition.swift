//
//  File.swift
//  swift-records
//
//  Created by Coen ten Thije Boonkkamp on 31/08/2025.
//

import Foundation
import StructuredQueriesPostgres

extension PrimaryKeyedTableDefinition {
    /// A query expression representing the number of rows in this table.
    ///
    /// - Parameters:
    ///   - isDistinct: Whether or not to include a `DISTINCT` clause, which filters duplicates from
    ///     the aggregation.
    ///   - filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: An expression representing the number of rows in this table.
    public func count(
        distinct isDistinct: Bool = false,
        filter: (some QueryExpression<Bool>)? = Bool?.none
    ) -> some QueryExpression<Int> {
        primaryKey.count(distinct: isDistinct, filter: filter)
    }
}
