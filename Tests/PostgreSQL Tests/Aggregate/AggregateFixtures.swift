import SQL
import SQL_Macros

enum AggregateFixtures {
    @Table("customers")
    struct Customer {
        let id: Int
        var name: String
    }

    @Table("purchases")
    struct Purchase {
        let id: Int
        var customerID: Int
        var amount: Double
        var discount: Double?
        var isPaid: Bool
    }
}
