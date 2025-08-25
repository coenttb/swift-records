import Foundation
import StructuredQueries
import StructuredQueriesPostgres
import DatabasePostgres

// MARK: - Test Models

@Table
struct User {
    let id: Int
    var name: String
    var email: String
    var createdAt: Date
}

@Table
struct Post {
    let id: Int
    var userId: Int
    var title: String
    var content: String
    var publishedAt: Date?
}

@Table
struct Comment {
    let id: Int
    var postId: Int
    var userId: Int
    var text: String
    var createdAt: Date
}

@Table
struct Tag {
    let id: Int
    var name: String
}

@Table
struct PostTag {
    var postId: Int
    var tagId: Int
}
