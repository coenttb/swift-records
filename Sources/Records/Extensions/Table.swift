//
//  File.swift
//  swift-records
//
//  Created by Coen ten Thije Boonkkamp on 31/08/2025.
//

import Foundation

extension Table {
    /// A select statement for this table's row count.
    ///
    /// - Parameter filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A select statement that selects `count(*)`.
    public static func count(
        filter: ((TableColumns) -> any QueryExpression<Bool>)? = nil
    ) -> Select<Int, Self, ()> {
        Where().count(filter: filter)
    }
}
