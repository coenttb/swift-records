import SQL
import SQL_Macros

enum WindowFixtures {
    @Table("scores")
    struct Score {
        let id: Int
        var playerID: Int
        var points: Int
    }

    @Table("stock_prices")
    struct StockPrice {
        let id: Int
        var symbol: String
        var day: Int
        var price: Double
    }
}
