import Foundation
import Records
import StructuredQueriesPostgres

// MARK: - Test Models (User/Post Schema)
//
// Note: User and Tag are defined in ReminderSchema.swift (upstream-aligned)
// These models are for swift-records-specific tests

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
package struct PostTag {
    package var postId: Int
    package var tagId: Int
}
