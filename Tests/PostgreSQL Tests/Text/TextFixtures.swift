import SQL
import SQL_Macros

enum TextFixtures {
    @Table("people")
    struct Person {
        let id: Int
        let name: String
        let nickname: String?
    }
}
