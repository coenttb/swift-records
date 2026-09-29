import SQL
import SQL_Macros

enum TriggerFixtures {
    @Table("orders")
    struct Order: Codable, Equatable {
        let id: Int
        var status: String
        var total: Double
    }
}
