internal import ISO_9075_Foundation
public import SQL

extension PostgreSQL {
    public enum Math {}
}

extension PostgreSQL.Math {
    public static func pi() -> some QueryExpression<Double> {
        SQLQueryExpression("pi()", as: Double.self)
    }

    public static func random() -> some QueryExpression<Double> {
        SQLQueryExpression("random()", as: Double.self)
    }

    public static func setseed(_ seed: some QueryExpression<Double>) -> some QueryExpression<Void> {
        SQLQueryExpression("setseed(\(seed))", as: Void.self)
    }
}
