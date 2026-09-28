import SQL
import SQL_Macros

enum SubqueryFixtures {
    @Table("shop_products")
    struct Product {
        let id: Int
        var name: String
        var price: Double
    }

    @Table("featured_products")
    struct Featured {
        let id: Int
        var productID: Int
    }
}
