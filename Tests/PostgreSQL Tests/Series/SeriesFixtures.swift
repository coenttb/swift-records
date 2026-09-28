import PostgreSQL
import SQL
import SQL_Macros
import Time

enum SeriesFixtures {
    @Table("posts")
    struct Post {
        let id: Int
        var title: String
        @Column(as: PostgreSQL.Array<String>.self)
        var tags: [String]
    }

    @Table("events")
    struct Event {
        let id: Int
        var startsAt: Time.Instant
        var endsAt: Time.Instant
    }
}
