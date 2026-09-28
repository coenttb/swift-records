import SQL
import SQL_Macros

enum PatternFixtures {
    @Table("documents")
    struct Document {
        let id: Int
        let title: String
    }
}
