import Byte
import SQL
import SQL_Macros

enum BinaryFixtures {
    @Table("attachments")
    struct Attachment {
        let id: Int
        let content: [Byte]
        let digest: String
    }
}
