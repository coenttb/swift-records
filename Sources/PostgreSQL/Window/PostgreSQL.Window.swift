internal import ISO_9075_Foundation

extension PostgreSQL {
    public enum Window {}
}

extension PostgreSQL.Window {
    public static func rowNumber() -> Function<Int> {
        Function("ROW_NUMBER")
    }

    public static func rank() -> Function<Int> {
        Function("RANK")
    }

    public static func denseRank() -> Function<Int> {
        Function("DENSE_RANK")
    }

    public static func percentRank() -> Function<Double> {
        Function("PERCENT_RANK")
    }

    public static func cumeDist() -> Function<Double> {
        Function("CUME_DIST")
    }

    public static func ntile(_ buckets: Int) -> Function<Int> {
        precondition(buckets > 0, "ntile buckets must be positive")
        return Function("NTILE", ["\(raw: buckets)"])
    }
}
