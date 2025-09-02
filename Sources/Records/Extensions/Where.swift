//
//  File.swift
//  swift-records
//
//  Created by Coen ten Thije Boonkkamp on 31/08/2025.
//

import Foundation
import StructuredQueriesPostgres

extension Where {

    /// A select statement for the filtered table's row count.
    ///
    /// - Parameter filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A select statement that selects `count(*)`.
    public func count(
        filter: ((From.TableColumns) -> any QueryExpression<Bool>)? = nil
    ) -> Select<Int, From, ()> {
        asSelect().count(filter: filter)
    }
}
