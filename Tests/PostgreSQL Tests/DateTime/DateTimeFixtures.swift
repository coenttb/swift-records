import SQL
import SQL_Macros
import Time

enum DateTimeFixtures {
    @Table("events")
    struct Event {
        let id: Int
        let title: String
        let timestamp: Time.Instant
    }
}
