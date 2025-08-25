import Foundation
import Records
import StructuredQueriesPostgres

// MARK: - Test Models

@Table
package struct User {
    package let id: Int
    package var name: String
    package var email: String
    package var createdAt: Date
}

@Table
package struct Post {
    package let id: Int
    package var userId: Int
    package var title: String
    package var content: String
    package var publishedAt: Date?
}

@Table
package struct Comment {
    package let id: Int
    package var postId: Int
    package var userId: Int
    package var text: String
    package var createdAt: Date
}

@Table
package struct Tag {
    package let id: Int
    package var name: String
}

@Table
package struct PostTag {
    package var postId: Int
    package var tagId: Int
}
