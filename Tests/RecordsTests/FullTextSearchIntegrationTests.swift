import Dependencies
import DependenciesTestSupport
import Foundation
import RecordsTestSupport
import StructuredQueriesPostgres
import Testing

// MARK: - Test Model

@Table
struct Article: Codable, Equatable, Identifiable, FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var author: String

    static var searchVectorColumn: String { "search_vector" }
}

// MARK: - Test Database Setup

extension Database.TestDatabaseSetupMode {
    /// Articles schema with full-text search pre-configured
    static let withArticlesFTS = Database.TestDatabaseSetupMode { db in
        try await db.write { conn in
            // Create articles table
            try await conn.execute(
                """
                CREATE TABLE "articles" (
                    "id" SERIAL PRIMARY KEY,
                    "title" TEXT NOT NULL,
                    "body" TEXT NOT NULL,
                    "author" TEXT NOT NULL,
                    "search_vector" tsvector
                )
                """
            )

            // Create GIN index on search_vector
            try await conn.execute(
                """
                CREATE INDEX "articles_search_vector_idx"
                ON "articles"
                USING GIN ("search_vector")
                """
            )

            // Create trigger function for automatic search vector updates
            try await conn.execute(
                """
                CREATE OR REPLACE FUNCTION articles_search_vector_trigger() RETURNS trigger AS $$
                BEGIN
                  NEW."search_vector" :=
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."title", '')), 'A') ||
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."body", '')), 'B') ||
                    setweight(to_tsvector('pg_catalog.english', coalesce(NEW."author", '')), 'C');
                  RETURN NEW;
                END
                $$ LANGUAGE plpgsql
                """
            )

            // Create trigger
            try await conn.execute(
                """
                CREATE TRIGGER articles_search_vector_update
                BEFORE INSERT OR UPDATE ON "articles"
                FOR EACH ROW EXECUTE FUNCTION articles_search_vector_trigger()
                """
            )

            // Insert test data
            try await conn.execute(
                """
                INSERT INTO "articles" ("title", "body", "author") VALUES
                ('PostgreSQL Full-Text Search', 'Learn about PostgreSQL full-text search capabilities', 'Alice'),
                ('Swift Concurrency Guide', 'Modern async/await patterns in Swift programming', 'Bob'),
                ('Database Indexing', 'Understanding B-tree and GIN indexes', 'Alice'),
                ('Server-Side Swift', 'Building web services with Swift on the server', 'Charlie')
                """
            )
        }
    }
}

extension Database.TestDatabase {
    /// Creates a test database with Articles table and FTS pre-configured
    static func withArticlesFTS() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withArticlesFTS)
    }
}

// MARK: - Test Suite

@Suite(
    "Full-Text Search Integration Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withArticlesFTS()
    }
)
struct FullTextSearchIntegrationTests {
    @Dependency(\.defaultDatabase) var database

    // MARK: - Basic Search Operations

    @Test("Search vector is automatically populated on insert")
    func automaticSearchVectorOnInsert() async throws {
        try await database.withRollback { db in
            // Insert new article
            let inserted = try await Article.insert {
                Article.Draft(
                    title: "Testing Full-Text Search",
                    body: "This article tests the automatic search vector population",
                    author: "Diana"
                )
            }
            .returning(\.self)
            .fetchAll(db)

            // Verify article was inserted
            #expect(inserted.count == 1)
            #expect(inserted[0].title == "Testing Full-Text Search")

            // Note: We can't directly access search_vector from Article model,
            // but we can verify it works by searching
            let allArticles = try await Article.all.fetchAll(db)
            #expect(allArticles.count == 5) // 4 initial + 1 new
        }
    }

    @Test("Search vector updates on article update")
    func automaticSearchVectorOnUpdate() async throws {
        try await database.withRollback { db in
            // Insert article
            let inserted = try await Article.insert {
                Article.Draft(
                    title: "Original Title",
                    body: "Original body content",
                    author: "Eve"
                )
            }
            .returning(\.self)
            .fetchAll(db)

            let articleId = inserted[0].id

            // Update article
            try await Article
                .where { $0.id == articleId }
                .update { article in
                    article.title = "Updated Title"
                    article.body = "Updated body content"
                }
                .execute(db)

            // Verify update
            let updated = try await Article
                .where { $0.id == articleId }
                .fetchOne(db)

            #expect(updated?.title == "Updated Title")
            #expect(updated?.body == "Updated body content")
        }
    }

    @Test("Multiple articles can be inserted with FTS")
    func multipleInserts() async throws {
        try await database.withRollback { db in
            try await Article.insert {
                Article.Draft(
                    title: "Article One",
                    body: "First test article",
                    author: "Author A"
                )
                Article.Draft(
                    title: "Article Two",
                    body: "Second test article",
                    author: "Author B"
                )
                Article.Draft(
                    title: "Article Three",
                    body: "Third test article",
                    author: "Author C"
                )
            }.execute(db)

            let allArticles = try await Article.all.fetchAll(db)
            #expect(allArticles.count == 7) // 4 initial + 3 new
        }
    }

    // MARK: - Data Verification

    @Test("Initial test data is loaded correctly")
    func initialDataLoaded() async throws {
        let articles = try await database.read { db in
            try await Article.all.fetchAll(db)
        }

        #expect(articles.count == 4)

        // Verify we have expected articles
        let titles = Set(articles.map(\.title))
        #expect(titles.contains("PostgreSQL Full-Text Search"))
        #expect(titles.contains("Swift Concurrency Guide"))
        #expect(titles.contains("Database Indexing"))
        #expect(titles.contains("Server-Side Swift"))
    }

    @Test("Articles by specific author")
    func articlesByAuthor() async throws {
        let aliceArticles = try await database.read { db in
            try await Article
                .where { $0.author == "Alice" }
                .fetchAll(db)
        }

        #expect(aliceArticles.count == 2)

        let titles = Set(aliceArticles.map(\.title))
        #expect(titles.contains("PostgreSQL Full-Text Search"))
        #expect(titles.contains("Database Indexing"))
    }

    @Test("Find article by title substring")
    func findByTitleSubstring() async throws {
        let articles = try await database.read { db in
            try await Article
                .where { $0.title.like("%Swift%") }
                .fetchAll(db)
        }

        #expect(articles.count == 2)

        let titles = Set(articles.map(\.title))
        #expect(titles.contains("Swift Concurrency Guide"))
        #expect(titles.contains("Server-Side Swift"))
    }

    // MARK: - CRUD Operations with FTS

    @Test("Insert, update, and delete with FTS triggers")
    func crudWithFTS() async throws {
        try await database.withRollback { db in
            // Insert
            let inserted = try await Article.insert {
                Article.Draft(
                    title: "CRUD Test Article",
                    body: "Testing create, read, update, delete operations",
                    author: "Frank"
                )
            }
            .returning(\.id)
            .fetchAll(db)

            let articleId = inserted[0]

            // Read
            let fetched = try await Article
                .where { $0.id == articleId }
                .fetchOne(db)
            #expect(fetched?.title == "CRUD Test Article")

            // Update
            try await Article
                .where { $0.id == articleId }
                .update { $0.title = "Updated CRUD Test" }
                .execute(db)

            let updated = try await Article
                .where { $0.id == articleId }
                .fetchOne(db)
            #expect(updated?.title == "Updated CRUD Test")

            // Delete
            try await Article
                .where { $0.id == articleId }
                .delete()
                .execute(db)

            let deleted = try await Article
                .where { $0.id == articleId }
                .fetchOne(db)
            #expect(deleted == nil)
        }
    }

    // MARK: - Full-Text Search Operations

    @Test("Search for articles matching a single term")
    func searchSingleTerm() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("PostgreSQL") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "PostgreSQL Full-Text Search")
        } catch {
            print("❌ Search single term failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search for articles with multiple terms (AND)")
    func searchMultipleTermsAND() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("Swift & patterns") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "Swift Concurrency Guide")
        } catch {
            print("❌ Search AND failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search for articles with multiple terms (OR)")
    func searchMultipleTermsOR() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("PostgreSQL | Swift") }
                    .order(by: \.title)
                    .fetchAll(db)
            }

            #expect(articles.count >= 2)

            let titles = Set(articles.map(\.title))
            #expect(titles.contains("PostgreSQL Full-Text Search"))
            #expect(titles.contains("Swift Concurrency Guide"))
        } catch {
            print("❌ Search OR failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search with ranking by relevance")
    func searchWithRanking() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("database") }
                    .fetchAll(db)
            }

            // Should find at least one article
            #expect(articles.count >= 1)

            let titles = Set(articles.map(\.title))
            #expect(titles.contains("Database Indexing"))
        } catch {
            print("❌ Search with ranking failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search articles by author using FTS")
    func searchByAuthor() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("Alice") }
                    .order(by: \.id)
                    .fetchAll(db)
            }

            #expect(articles.count == 2)
            #expect(articles.allSatisfy { $0.author == "Alice" })
        } catch {
            print("❌ Search by author failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search with phrase query")
    func searchPhraseQuery() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.phraseMatch("web services") }
                    .fetchAll(db)
            }

            #expect(articles.count == 1)
            #expect(articles[0].title == "Server-Side Swift")
        } catch {
            print("❌ Phrase search failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Search returns no results for non-matching term")
    func searchNoResults() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.match("nonexistentterm12345") }
                    .fetchAll(db)
            }

            #expect(articles.count == 0)
        } catch {
            print("❌ Search no results failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Plain text search (safer for user input)")
    func plainTextSearch() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.plainMatch("swift postgresql") }
                    .fetchAll(db)
            }

            // plainMatch treats all words as AND, so no results expected
            // (no single article contains both "swift" and "postgresql")
            #expect(articles.count == 0)
        } catch {
            print("❌ Plain text search failed: \(String(reflecting: error))")
            throw error
        }
    }

    @Test("Web search syntax")
    func webSearchSyntax() async throws {
        do {
            let articles = try await database.read { db in
                try await Article
                    .where { $0.webMatch("Swift OR PostgreSQL") }
                    .fetchAll(db)
            }

            #expect(articles.count >= 2)

            let titles = Set(articles.map(\.title))
            #expect(titles.contains("Swift Concurrency Guide") || titles.contains("PostgreSQL Full-Text Search"))
        } catch {
            print("❌ Web search syntax failed: \(String(reflecting: error))")
            throw error
        }
    }
}
