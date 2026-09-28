public import ISO_9075_Foundation
public import SQL

extension PostgreSQL.Window {
    public struct Function<QueryValue>: QueryExpression, Sendable {
        let name: String
        let arguments: [ISO_9075.Fragment]
        let specification: Specification

        init(
            _ name: String,
            _ arguments: [ISO_9075.Fragment] = [],
            specification: Specification = Specification()
        ) {
            self.name = name
            self.arguments = arguments
            self.specification = specification
        }

        public func over() -> Self {
            Self(name, arguments)
        }

        public func over(_ specify: (Specification) -> Specification) -> Self {
            Self(name, arguments, specification: specify(Specification()))
        }

        public var queryFragment: ISO_9075.Fragment {
            "\(raw: name)(\(arguments.joined(separator: ", "))) OVER (\(specification.queryFragment))"
        }
    }
}
