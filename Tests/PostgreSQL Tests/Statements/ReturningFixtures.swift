import SQL
import SQL_Macros

enum ReturningFixtures {
    @Table("notes")
    struct Note {
        let id: Int
        var body: String
    }
}
