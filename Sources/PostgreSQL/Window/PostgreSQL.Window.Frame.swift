internal import ISO_9075_Foundation

extension PostgreSQL.Window {
    public struct Frame: Sendable, Hashable {
        public let unit: Unit
        public let start: Bound
        public let end: Bound?

        public init(_ unit: Unit, from start: Bound, to end: Bound? = nil) {
            self.unit = unit
            self.start = start
            self.end = end
        }

        var queryFragment: ISO_9075.Fragment {
            switch end {
            case let end?: "\(raw: unit.rawValue) BETWEEN \(start.queryFragment) AND \(end.queryFragment)"
            case nil: "\(raw: unit.rawValue) \(start.queryFragment)"
            }
        }
    }
}
