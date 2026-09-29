import PostgreSQL
import SQL
import SQL_Macros

enum TextSearchFixtures {
    @Table("documents")
    struct Document {
        let id: Int
        var title: String
        var body: String?
        var search: PostgreSQL.TextSearch.Vector
    }
}
