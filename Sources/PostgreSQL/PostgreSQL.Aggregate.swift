public import ISO_9075_Foundation
public import SQL

extension PostgreSQL {
    public struct Aggregate<QueryValue>: QueryExpression, Sendable {
        let name: String
        let isDistinct: Bool
        let arguments: [ISO_9075.Fragment]
        let order: ISO_9075.Fragment?
        let filter: ISO_9075.Fragment?

        init(
            _ name: String,
            distinct isDistinct: Bool = false,
            _ arguments: [ISO_9075.Fragment],
            order: ISO_9075.Fragment? = nil,
            filter: ISO_9075.Fragment? = nil
        ) {
            self.name = name
            self.isDistinct = isDistinct
            self.arguments = arguments
            self.order = order
            self.filter = filter
        }

        public var queryFragment: ISO_9075.Fragment {
            let distinct: ISO_9075.Fragment = isDistinct ? "DISTINCT " : ""
            let order: ISO_9075.Fragment = self.order.map { " ORDER BY \($0)" } ?? ""
            let filter: ISO_9075.Fragment = self.filter.map { " FILTER (WHERE \($0))" } ?? ""
            return "\(raw: name)(\(distinct)\(arguments.joined(separator: ", "))\(order))\(filter)"
        }
    }
}
