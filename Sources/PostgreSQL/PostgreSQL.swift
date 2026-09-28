public import ISO_9075_Foundation

public struct PostgreSQL: ISO_9075.Dialect {
    public init() {}

    public func placeholder(_ offset: Int) -> String { "$\(offset)" }
}
