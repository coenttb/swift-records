import SQL
import SQL_Macros
import Time

enum FormattingFixtures {
    @Table("invoices")
    struct Invoice {
        let id: Int
        let amount: Double
        let issuedAt: Time.Instant
        let reference: String
    }
}
