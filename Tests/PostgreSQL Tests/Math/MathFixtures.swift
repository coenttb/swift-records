import SQL
import SQL_Macros

enum MathFixtures {
    @Table("measurements")
    struct Measurement {
        let id: Int
        var value: Double
        var angle: Double
    }

    @Table("numbers")
    struct Number {
        let id: Int
        var value: Int
        var divisor: Int
    }
}
