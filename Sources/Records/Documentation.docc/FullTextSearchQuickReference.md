# Full-Text Search Quick Reference

Quick reference guide for common PostgreSQL full-text search operations.

## Overview

This cheat sheet provides concise examples for the most common full-text search operations. For comprehensive documentation, see the <doc:FullTextSearch> guide. For architectural details, see <doc:FullTextSearchArchitecture>.

---

## Setup

### Basic Setup

```swift
@Table
struct Article: FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var search_vector: TextSearch.Vector  // Column name matches default
}

// Setup in migration
try await db.write { db in
    try await db.execute(Article.createTable())
    try await db.setupFullTextSearch(
        for: Article.self,
        trackingColumns: [\.$title, \.$body],
        language: "english",
        weights: [.A, .B],  // title=A (high), body=B (medium)
        indexType: .gin     // Default, fast searches
    )
}
```

---

## Search Operations

### Basic Search

```swift
// Simple word search
let results = try await Article
    .where { $0.match("swift") }
    .fetchAll(db)

// Multiple words (AND operator)
let results = try await Article
    .where { $0.match("swift & vapor") }
    .fetchAll(db)

// OR operator
let results = try await Article
    .where { $0.match("swift | rust") }
    .fetchAll(db)

// NOT operator
let results = try await Article
    .where { $0.match("swift & !sqlite") }
    .fetchAll(db)
```

### Search Methods

| Method | PostgreSQL Function | Use Case | Example |
|--------|---------------------|----------|---------|
| `match()` | `to_tsquery()` | Standard search with operators | `$0.match("swift & vapor")` |
| `plainMatch()` | `plainto_tsquery()` | Plain text (no operators) | `$0.plainMatch("swift vapor")` |
| `webMatch()` | `websearch_to_tsquery()` | Web search syntax | `$0.webMatch('"swift vapor" -sqlite')` |
| `phraseMatch()` | `phraseto_tsquery()` | Exact phrase matching | `$0.phraseMatch("swift programming")` |

#### Examples

```swift
// Standard match (supports operators)
Article.where { $0.match("swift & vapor") }

// Plain match (treats operators as literal text)
Article.where { $0.plainMatch("swift & vapor") }  // Searches for "&" literally

// Web match (supports quotes and minus)
Article.where { $0.webMatch('"swift programming" -sqlite') }

// Phrase match (exact phrase in order)
Article.where { $0.phraseMatch("swift programming") }
```

### Language-Specific Search

```swift
// Specify language
let results = try await Article
    .where { $0.match("running", language: "english") }
    .fetchAll(db)
// Matches: run, runs, running, ran (stemmed)

// Spanish search
let results = try await Article
    .where { $0.match("corriendo", language: "spanish") }
    .fetchAll(db)
// Matches: correr, corre, corriendo, corrió (stemmed)

// No stemming (simple configuration)
let results = try await Article
    .where { $0.match("running", language: "simple") }
    .fetchAll(db)
// Matches: running (exact, no stemming)
```

---

## Ranking

### Basic Ranking

```swift
// Get articles ranked by relevance
let results = try await Article
    .select { article in
        (article, article.rank("swift"))
    }
    .where { $0.match("swift") }
    .order { $0.rank("swift").desc }
    .limit(20)
    .fetchAll(db)

// Access rank in results
for (article, rank) in results {
    print("\(article.title): \(rank)")
}
```

### Ranking Functions

| Function | PostgreSQL | Description |
|----------|-----------|-------------|
| `rank()` | `ts_rank()` | Standard TF-IDF ranking |
| `rankCD()` | `ts_rank_cd()` | Cover density ranking (considers word proximity) |

```swift
// Standard ranking
Article.where { $0.match("swift") }
    .order { $0.rank("swift").desc }

// Cover density ranking (better for phrase proximity)
Article.where { $0.match("swift vapor") }
    .order { $0.rankCD("swift vapor").desc }
```

### Normalization Options

```swift
import StructuredQueriesPostgres

// No normalization (default)
.rank("swift")

// Divide by document length (normalize for document size)
.rank("swift", normalization: .divideByDocumentLength)

// Multiple normalizations
.rank("swift", normalization: [
    .divideByDocumentLength,
    .divideByNumberOfUniqueWords
])
```

**Normalization Options**:
- `.divideByDocumentLength` - Normalize by document length
- `.divideByNumberOfUniqueWords` - Normalize by unique word count
- `.divideByHarmonicDistanceOfExtents` - Normalize by word proximity
- `.divideByNumberOfUniqueExtents` - Normalize by extent count
- `.considerDocumentLength` - Add document length to rank
- `.considerRankOfEachExtent` - Add extent ranks

---

## Search Operators

### Boolean Operators

| Operator | Symbol | Example | Matches |
|----------|--------|---------|---------|
| AND | `&` | `"swift & vapor"` | Documents containing both "swift" AND "vapor" |
| OR | `\|` | `"swift \| rust"` | Documents containing "swift" OR "rust" |
| NOT | `!` | `"swift & !sqlite"` | Documents containing "swift" but NOT "sqlite" |

### Phrase Operators

| Operator | Symbol | Example | Matches |
|----------|--------|---------|---------|
| Followed by | `<->` | `"swift <-> programming"` | "swift" immediately followed by "programming" |
| Followed by (distance) | `<N>` | `"swift <2> vapor"` | "swift" followed by "vapor" within 2 words |

### Prefix Search

```swift
// Search with prefix (wildcard)
Article.where { $0.match("swif:*") }
// Matches: swift, swiftly, swifter, etc.

// Combine with other operators
Article.where { $0.match("swif:* & programming") }
// Matches: documents with words starting with "swif" AND "programming"
```

---

## Combining with Other Queries

### Filter + Search

```swift
// Combine full-text search with regular filters
let results = try await Article
    .where { article in
        article.match("swift") && article.publishedAt > Date().addingTimeInterval(-30 * 86400)
    }
    .fetchAll(db)
```

### Search + Sort + Limit

```swift
// Search, rank, and paginate
let results = try await Article
    .where { $0.match("swift") }
    .order { $0.rank("swift").desc }
    .limit(20)
    .offset(0)
    .fetchAll(db)
```

### Complex Queries

```swift
// Multi-criteria search with ranking
let results = try await Article
    .select { article in
        (
            article,
            article.rank("swift"),
            article.publishedAt
        )
    }
    .where { article in
        article.match("swift") &&
        article.status == .published &&
        article.authorId == currentUserId
    }
    .order { article in
        (
            article.rank("swift").desc,
            article.publishedAt.desc
        )
    }
    .limit(10)
    .fetchAll(db)
```

---

## Common Patterns

### Search with Fallback

```swift
// Try exact phrase first, fall back to plain text
func search(_ query: String) async throws -> [Article] {
    // Try exact phrase
    let exactResults = try await Article
        .where { $0.phraseMatch(query) }
        .limit(10)
        .fetchAll(db)

    if !exactResults.isEmpty {
        return exactResults
    }

    // Fall back to plain text search
    return try await Article
        .where { $0.plainMatch(query) }
        .limit(10)
        .fetchAll(db)
}
```

### Autocomplete Search

```swift
// Prefix search for autocomplete
func autocomplete(_ prefix: String) async throws -> [String] {
    let results = try await Article
        .select { $0.title }
        .where { $0.match("\(prefix):*") }
        .limit(10)
        .fetchAll(db)

    return results.map(\.title)
}
```

### Multi-Field Weighted Search

```swift
@Table
struct Product: FullTextSearchable {
    let id: Int
    var name: String        // Weight A (highest priority)
    var description: String // Weight B
    var tags: String        // Weight C
    var search_vector: TextSearch.Vector
}

// Setup with weights
try await db.setupFullTextSearch(
    for: Product.self,
    trackingColumns: [\.$name, \.$description, \.$tags],
    weights: [.A, .B, .C]  // name > description > tags
)

// Search (weights automatically applied in ranking)
let results = try await Product
    .where { $0.match("widget") }
    .order { $0.rank("widget").desc }  // Higher rank if "widget" in name
    .fetchAll(db)
```

### Category-Scoped Search

```swift
// Search within a specific category
func searchInCategory(_ query: String, category: String) async throws -> [Product] {
    try await Product
        .where { product in
            product.match(query) && product.category == category
        }
        .order { $0.rank(query).desc }
        .fetchAll(db)
}
```

---

## Database Operations

### Index Management

```swift
// Create index (usually called via setupFullTextSearch)
try await db.createFullTextSearchIndex(
    for: Article.self,
    using: .gin  // or .gist
)

// Index types
.gin   // Default: Fast searches, slower updates
.gist  // Fast updates, slower searches (use for write-heavy workloads)
```

### Trigger Management

```swift
// Setup automatic tsvector updates
try await db.setupFullTextSearchTrigger(
    for: Article.self,
    trackingColumns: [\.$title, \.$body],
    language: "english",
    weights: [.A, .B]
)

// What this creates:
// 1. PostgreSQL function that generates tsvector
// 2. BEFORE INSERT OR UPDATE trigger that calls the function
```

### Backfill Existing Data

```swift
// Update existing rows (run after adding FTS to existing table)
try await db.backfillFullTextSearch(
    for: Article.self,
    trackingColumns: [\.$title, \.$body],
    language: "english",
    weights: [.A, .B]
)

// ⚠️ Warning: Can be slow for large tables (runs UPDATE on all rows)
```

### All-in-One Setup

```swift
// Complete FTS setup (index + trigger + backfill)
try await db.write { db in
    try await db.setupFullTextSearch(
        for: Article.self,
        trackingColumns: [\.$title, \.$body],
        language: "english",
        weights: [.A, .B],
        indexType: .gin
    )
}

// Equivalent to:
// 1. createFullTextSearchIndex()
// 2. setupFullTextSearchTrigger()
// 3. backfillFullTextSearch()
```

---

## Performance Tips

### Do's ✅

```swift
// ✅ Always create index
try await db.setupFullTextSearch(for: Article.self, ...)

// ✅ Use LIMIT for ranked queries
.where { $0.match("swift") }
.order { $0.rank("swift").desc }
.limit(20)  // Only rank top 20

// ✅ Track only searchable columns
trackingColumns: [\.$title, \.$body]  // Not [\.$id, \.$createdAt, ...]

// ✅ Use appropriate weights
weights: [.A, .B]  // title > body

// ✅ Use GIN index for read-heavy workloads (default)
indexType: .gin
```

### Don'ts ❌

```swift
// ❌ Don't search without index
// Results in full table scan - very slow!

// ❌ Don't rank all results without LIMIT
.where { $0.match("swift") }
.order { $0.rank("swift").desc }
// No limit = ranks all matches (slow for many results)

// ❌ Don't track non-searchable columns
trackingColumns: [\.$id, \.$createdAt, \.$updatedAt]
// Wastes space and slows down updates

// ❌ Don't use identical weights
weights: [.A, .A, .A]
// No differentiation - use [.A, .B, .C] instead
```

---

## Common Query Patterns

### Search Result Page

```swift
struct SearchResults {
    let articles: [(article: Article, rank: Double)]
    let total: Int
    let page: Int
    let perPage: Int
}

func searchArticles(
    query: String,
    page: Int = 1,
    perPage: Int = 20
) async throws -> SearchResults {
    let offset = (page - 1) * perPage

    // Get results with ranking
    let articles = try await Article
        .select { article in
            (article, article.rank(query))
        }
        .where { $0.match(query) }
        .order { $0.rank(query).desc }
        .limit(perPage)
        .offset(offset)
        .fetchAll(db)

    // Get total count (for pagination)
    let total = try await Article
        .where { $0.match(query) }
        .count()
        .fetchOne(db) ?? 0

    return SearchResults(
        articles: articles,
        total: total,
        page: page,
        perPage: perPage
    )
}
```

### Faceted Search

```swift
// Search with category facets
func facetedSearch(
    query: String,
    category: String? = nil
) async throws -> [Article] {
    var statement = Article
        .where { $0.match(query) }

    // Apply category filter if provided
    if let category = category {
        statement = statement.where { $0.category == category }
    }

    return try await statement
        .order { $0.rank(query).desc }
        .limit(20)
        .fetchAll(db)
}
```

### Search Suggestions (Did You Mean?)

```swift
// Simple suggestion: try prefix search if no exact results
func searchWithSuggestions(_ query: String) async throws -> ([Article], suggestion: String?) {
    // Try exact search
    let exactResults = try await Article
        .where { $0.match(query) }
        .limit(10)
        .fetchAll(db)

    if !exactResults.isEmpty {
        return (exactResults, suggestion: nil)
    }

    // Try prefix search (potential typo)
    let prefixResults = try await Article
        .where { $0.match("\(query.prefix(query.count - 1)):*") }
        .limit(10)
        .fetchAll(db)

    if !prefixResults.isEmpty {
        return (prefixResults, suggestion: "Did you mean '\(query.dropLast())*'?")
    }

    return ([], suggestion: nil)
}
```

---

## Migration Examples

### Adding FTS to Existing Table

```swift
// Migration: Add FTS to existing articles table
struct AddFullTextSearchToArticles: Migration {
    static let version: Int = 2

    static func up(_ db: any DatabaseProtocol) async throws {
        // 1. Add search_vector column
        try await db.execute("""
            ALTER TABLE articles
            ADD COLUMN search_vector TSVECTOR
            """)

        // 2. Setup FTS infrastructure
        try await db.setupFullTextSearch(
            for: Article.self,
            trackingColumns: [\.$title, \.$body],
            language: "english",
            weights: [.A, .B],
            indexType: .gin
        )
    }

    static func down(_ db: any DatabaseProtocol) async throws {
        // Cleanup
        try await db.execute("DROP TRIGGER IF EXISTS articles_search_vector_trigger ON articles")
        try await db.execute("DROP FUNCTION IF EXISTS articles_search_vector_update")
        try await db.execute("DROP INDEX IF EXISTS articles_search_vector_idx")
        try await db.execute("ALTER TABLE articles DROP COLUMN search_vector")
    }
}
```

### Changing Tracked Columns

```swift
// Migration: Add tags to search
struct AddTagsToArticleSearch: Migration {
    static let version: Int = 3

    static func up(_ db: any DatabaseProtocol) async throws {
        // Update trigger to include tags column
        try await db.setupFullTextSearchTrigger(
            for: Article.self,
            trackingColumns: [\.$title, \.$body, \.$tags],
            language: "english",
            weights: [.A, .B, .C]  // title > body > tags
        )

        // Backfill existing rows with new configuration
        try await db.backfillFullTextSearch(
            for: Article.self,
            trackingColumns: [\.$title, \.$body, \.$tags],
            language: "english",
            weights: [.A, .B, .C]
        )
    }

    static func down(_ db: any DatabaseProtocol) async throws {
        // Revert to previous configuration
        try await db.setupFullTextSearchTrigger(
            for: Article.self,
            trackingColumns: [\.$title, \.$body],
            language: "english",
            weights: [.A, .B]
        )

        try await db.backfillFullTextSearch(
            for: Article.self,
            trackingColumns: [\.$title, \.$body],
            language: "english",
            weights: [.A, .B]
        )
    }
}
```

---

## Troubleshooting

### No Results When Expected

```swift
// Problem: Search returns no results
Article.where { $0.match("programming") }

// Debugging steps:

// 1. Check if index exists
// SQL: \d articles
// Look for index on search_vector column

// 2. Check if trigger exists
// SQL: \df articles_search_vector_update
// Should show trigger function

// 3. Check search_vector column values
let article = try await Article.where { $0.id == 1 }.fetchOne(db)
print(article?.search_vector)  // Should not be nil or empty

// 4. Try simpler search
Article.where { $0.plainMatch("programming") }

// 5. Check language configuration
Article.where { $0.match("programming", language: "english") }
```

### Slow Queries

```swift
// Problem: Search queries are slow

// 1. Verify index is being used (PostgreSQL)
// SQL: EXPLAIN ANALYZE SELECT * FROM articles WHERE search_vector @@ to_tsquery('swift')
// Look for "Bitmap Index Scan on articles_search_vector_idx"

// 2. If no index scan, create index
try await db.createFullTextSearchIndex(for: Article.self, using: .gin)

// 3. Run ANALYZE to update query planner statistics
try await db.execute("ANALYZE articles")

// 4. Add LIMIT to ranked queries
Article
    .where { $0.match("swift") }
    .order { $0.rank("swift").desc }
    .limit(20)  // Don't rank all results!
```

### Trigger Not Updating

```swift
// Problem: New/updated articles don't appear in search

// 1. Check if trigger exists
// SQL: SELECT * FROM pg_trigger WHERE tgname = 'articles_search_vector_trigger'

// 2. If missing, recreate trigger
try await db.setupFullTextSearchTrigger(
    for: Article.self,
    trackingColumns: [\.$title, \.$body]
)

// 3. Backfill existing data
try await db.backfillFullTextSearch(
    for: Article.self,
    trackingColumns: [\.$title, \.$body]
)

// 4. Test with new insert
try await Article.insert {
    Article(title: "Test", body: "Test content")
}.execute(db)

let results = try await Article.where { $0.match("test") }.fetchAll(db)
print(results.count)  // Should be > 0
```

---

## Language Reference

### Supported Languages

Common PostgreSQL text search configurations:

- `danish` - Danish
- `dutch` - Dutch
- `english` - English (default)
- `finnish` - Finnish
- `french` - French
- `german` - German
- `hungarian` - Hungarian
- `italian` - Italian
- `norwegian` - Norwegian
- `portuguese` - Portuguese
- `romanian` - Romanian
- `russian` - Russian
- `simple` - No language-specific processing (no stemming)
- `spanish` - Spanish
- `swedish` - Swedish
- `turkish` - Turkish

Check available configurations:
```sql
SELECT cfgname FROM pg_ts_config;
```

---

## Related Documentation

- **<doc:FullTextSearch>** - Comprehensive full-text search guide
- **<doc:FullTextSearchArchitecture>** - Architecture and design decisions
- **PostgreSQL Documentation** - [Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
