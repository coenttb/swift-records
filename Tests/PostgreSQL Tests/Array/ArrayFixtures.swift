import PostgreSQL
import SQL
import SQL_Macros

enum ArrayFixtures {
    @Table("articles")
    struct Article {
        let id: Int
        var title: String
        @Column(as: PostgreSQL.Array<String>.self)
        var tags: [String]
        @Column(as: PostgreSQL.Array<String>?.self)
        var aliases: [String]?
    }
}
