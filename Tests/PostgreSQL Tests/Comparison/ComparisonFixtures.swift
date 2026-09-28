import SQL
import SQL_Macros

enum ComparisonFixtures {
    @Table("price_items")
    struct Item {
        let id: Int
        var price: Double
        var comparePrice: Double
        var note: String?
        var code: Int?
    }
}
