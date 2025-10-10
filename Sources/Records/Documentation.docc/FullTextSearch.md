# Full-Text Search

Implement powerful text search using PostgreSQL's full-text search capabilities.

## Overview

PostgreSQL provides sophisticated full-text search through `tsvector` and `tsquery` types. Swift Records wraps these in a type-safe, Swift-idiomatic API that makes implementing search features straightforward and safe.

Unlike simple `LIKE` queries that match substrings character-by-character, full-text search understands language semantics: stemming ("running" matches "run"), stop words (ignores common words like "the"), and relevance ranking. This makes it ideal for search features in blogs, documentation sites, e-commerce catalogs, and any application where users need to find content by meaning rather than exact text.

## Topics

### Getting Started
- <doc:FullTextSearch#Quick-Start>
- <doc:FullTextSearch#Understanding-searchVectorColumn>
- <doc:FullTextSearch#Setting-Up-Search>

### Search Operations
- <doc:FullTextSearch#Search-Methods>
- <doc:FullTextSearch#Ranking-Results>
- <doc:FullTextSearch#Highlighting-Matches>

### Advanced Topics
- <doc:FullTextSearch#Language-Support>
- <doc:FullTextSearch#Custom-Weighting>
- <doc:FullTextSearch#Performance-Considerations>

### Reference
- <doc:FullTextSearchQuickReference>
- <doc:FullTextSearchArchitecture>
- <doc:FullTextSearch#Complete-Example>

---

## Quick Start

### 1. Make Your Model Searchable

```swift
import Records
import StructuredQueriesPostgres

@Table
struct Article: FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var author: String

    // Specify the tsvector column name (defaults to "search_vector")
    static var searchVectorColumn: String { "search_vector" }
}
```

### 2. Set Up Search in a Migration

```swift
migrator.registerMigration("add_articles_fts") { db in
    // Add tsvector column
    try await db.execute("""
        ALTER TABLE articles
        ADD COLUMN search_vector tsvector
    """)

    // Create GIN index for fast searches
    try await db.execute("""
        CREATE INDEX articles_search_idx
        ON articles
        USING GIN (search_vector)
    """)

    // Create trigger to automatically update search vector
    try await db.execute("""
        CREATE OR REPLACE FUNCTION articles_search_trigger() RETURNS trigger AS $$
        BEGIN
          NEW.search_vector :=
            setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(NEW.body, '')), 'B') ||
            setweight(to_tsvector('english', coalesce(NEW.author, '')), 'C');
          RETURN NEW;
        END
        $$ LANGUAGE plpgsql
    """)

    try await db.execute("""
        CREATE TRIGGER articles_search_update
        BEFORE INSERT OR UPDATE ON articles
        FOR EACH ROW EXECUTE FUNCTION articles_search_trigger()
    """)

    // Backfill existing data
    try await db.execute("""
        UPDATE articles SET search_vector =
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(body, '')), 'B') ||
          setweight(to_tsvector('english', coalesce(author, '')), 'C')
    """)
}
```

### 3. Search Your Content

```swift
struct SearchService {
    @Dependency(\.defaultDatabase) var db

    func searchArticles(query: String) async throws -> [Article] {
        try await db.read { db in
            try await Article
                .where { $0.match(query) }
                .order { $0.rank(query) }
                .fetchAll(db)
        }
    }
}
```

---

## Understanding searchVectorColumn

### Why This Requirement Exists

PostgreSQL and SQLite have fundamentally different full-text search architectures, which necessitates different protocol designs.

#### SQLite FTS5 Architecture

SQLite uses **virtual tables** where the entire table IS the search index:

```swift
// SQLite FTS5
@Table
struct ReminderText: FTS5 {
    let title: String
    let notes: String
}

// Match operates on the entire table
ReminderText.where { $0.match("swift") }
// SQL: SELECT * FROM "reminderTexts" WHERE ("reminderTexts" MATCH 'swift')

// Protocol is just a marker
public protocol FTS5: Table {}  // No requirements!
```

#### PostgreSQL FTS Architecture

PostgreSQL uses **regular tables** with dedicated `tsvector` columns:

```swift
// PostgreSQL FTS
@Table
struct Article: FullTextSearchable {
    let id: Int
    let title: String
    let body: String
    var search_vector: TextSearch.Vector  // Dedicated search column

    static var searchVectorColumn: String { "search_vector" }
}

// Match operates on specific column
Article.where { $0.match("swift") }
// SQL: SELECT * FROM "articles"
//      WHERE "articles"."search_vector" @@ to_tsquery('english', 'swift')
```

#### The Key Difference

| Aspect | SQLite FTS5 | PostgreSQL FTS |
|--------|-------------|----------------|
| **Architecture** | Virtual table (entire table is index) | Regular table + tsvector column |
| **Match Target** | Table-level | Column-level |
| **Multiple Indexes** | Create multiple virtual tables | Add multiple tsvector columns |
| **Protocol Requirement** | None (marker only) | Column name (must target specific column) |

**Why PostgreSQL needs `searchVectorColumn`**: A PostgreSQL table can have multiple tsvector columns for different purposes (e.g., English vs Spanish search, or separate indexes for titles vs content). The protocol must know which column to target.

### Convention with Flexibility

The protocol provides a default implementation that covers 95% of use cases:

```swift
extension FullTextSearchable {
    public static var searchVectorColumn: String { "search_vector" }
}
```

This means most tables work without any override:

```swift
@Table
struct Article: FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var search_vector: TextSearch.Vector  // Uses default "search_vector"
    // No override needed!
}
```

Only customize when your schema differs:

```swift
@Table
struct Article: FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var searchVector: TextSearch.Vector  // camelCase preference

    static var searchVectorColumn: String { "searchVector" }
}
```

### Why Not Other Approaches?

We evaluated several alternatives before settling on the protocol requirement:

1. **No requirement (like FTS5)** ❌
   - Impossible: PostgreSQL requires column specification
   - Cannot generate valid SQL without knowing column name

2. **Runtime column discovery** ❌
   - Runtime errors instead of compile-time safety
   - Performance cost of reflection on every query
   - Ambiguous with multiple tsvector columns

3. **Macro-generated property** ❌
   - Requires modifying upstream @Table macro
   - Tightly couples PostgreSQL concerns to shared code

4. **Current: Protocol requirement with default** ✅
   - Compile-time safety
   - Zero runtime overhead
   - Convention covers most cases
   - Explicit and debuggable

See <doc:FullTextSearchArchitecture#Protocol-Design> for detailed analysis.

---

## Setting Up Search

### Complete Setup Process

The setup process involves four steps that must be done once per table:

1. **Add tsvector column**
2. **Create automatic update trigger**
3. **Backfill existing data**
4. **Create GIN or GiST index**

#### Using Database Helpers

Swift Records provides helpers that handle this automatically:

```swift
try await db.write { db in
    try await db.setupFullTextSearch(
        on: "articles",
        column: "search_vector",
        weightedColumns: [
            .init(name: "title", weight: .A),
            .init(name: "body", weight: .B),
            .init(name: "author", weight: .C)
        ],
        language: "english",
        indexMethod: .gin
    )
}
```

This single call performs all four steps automatically.

#### Manual Setup (Alternative)

For more control, you can perform each step manually:

```swift
// Step 1: Add column
try await db.addSearchVectorColumn(
    to: "articles",
    column: "search_vector"
)

// Step 2: Create trigger
try await db.createSearchVectorTrigger(
    on: "articles",
    column: "search_vector",
    weightedColumns: [
        .init(name: "title", weight: .A),
        .init(name: "body", weight: .B)
    ],
    language: "english",
    type: .custom
)

// Step 3: Backfill
try await db.backfillSearchVector(
    table: "articles",
    column: "search_vector",
    weightedColumns: [
        .init(name: "title", weight: .A),
        .init(name: "body", weight: .B)
    ]
)

// Step 4: Create index
try await db.createGINIndex(
    on: "articles",
    column: "search_vector"
)
```

---

## Search Methods

Swift Records provides four search methods optimized for different use cases:

### match() - Boolean Search

Uses PostgreSQL's `to_tsquery()` for powerful boolean searches with operators:

```swift
// Single term
Article.where { $0.match("Swift") }

// Boolean AND - both terms must match
Article.where { $0.match("Swift & PostgreSQL") }

// Boolean OR - either term can match
Article.where { $0.match("Swift | Rust") }

// Negation - must NOT contain term
Article.where { $0.match("Swift & !Objective-C") }

// Phrase search with adjacency
Article.where { $0.match("quick <-> brown") }  // Words must be adjacent
Article.where { $0.match("quick <2> brown") }  // Within 2 words
```

**Use when**: You need full control over search logic

**Warning**: User input must be sanitized - invalid syntax causes PostgreSQL errors

### plainMatch() - Safe User Input

Uses `plainto_tsquery()` which treats all words as AND-connected terms:

```swift
// User enters: "swift postgresql database"
// Automatically becomes: swift & postgresql & database
Article.where { $0.plainMatch(userInput) }
```

**Use when**: Accepting untrusted user input

**Benefit**: Cannot cause syntax errors, always safe

### webMatch() - Google-like Syntax

Uses `websearch_to_tsquery()` for familiar web search syntax:

```swift
// Quoted phrases
Article.where { $0.webMatch(#""swift postgresql" database"#) }

// Exclusions with minus
Article.where { $0.webMatch("swift -objective-c") }

// OR operator
Article.where { $0.webMatch("Swift OR Rust") }
```

**Use when**: Building user-facing search with familiar syntax

**Benefit**: End users understand the query syntax

### phraseMatch() - Exact Phrases

Uses `phraseto_tsquery()` for exact phrase matching where words must appear in order:

```swift
// Finds "San Francisco" but not "Francisco's San Diego trip"
Article.where { $0.phraseMatch("San Francisco") }
```

**Use when**: Searching for named entities, quotes, or specific phrases

---

## Ranking Results

Order search results by relevance using PostgreSQL's ranking functions:

### Basic Ranking

```swift
Article
    .where { $0.match("Swift") }
    .order { $0.rank("Swift") }
    .fetchAll(db)
```

### Weighted Ranking

Prioritize matches in certain fields (e.g., title over body):

```swift
Article
    .where { $0.match("Swift") }
    .order {
        $0.rank(
            "Swift",
            weights: [0.1, 0.2, 0.4, 1.0]  // [D, C, B, A]
        )
    }
    .fetchAll(db)
```

**Weight Labels**:
- **A** - Highest importance (typically titles)
- **B** - High importance (typically subtitles, emphasized text)
- **C** - Medium importance (typically metadata, tags)
- **D** - Lowest importance (typically body text)

The weights array corresponds to `[D, C, B, A]` - this matches PostgreSQL's internal ordering.

### Coverage-Based Ranking

Better for phrase searches - considers proximity and coverage:

```swift
Article
    .where { $0.match("database indexing") }
    .order { $0.rankCoverage("database indexing") }
    .fetchAll(db)
```

### Normalization

Control how document length affects ranking:

```swift
// Reduce length bias (recommended)
Article.order { $0.rank("Swift", normalization: .divideByLogLength) }

// Heavily penalize long documents
Article.order { $0.rank("Swift", normalization: .divideByLength) }

// Multiple normalizations
Article.order {
    $0.rank("Swift", normalization: [.divideByLogLength, .divideByUniqueWordCount])
}
```

**Available Normalizations**:
- `.none` - No normalization (default)
- `.divideByLogLength` - Divide by (1 + log of length) - recommended
- `.divideByLength` - Divide by length
- `.divideByMeanHarmonicDistance` - Consider term proximity
- `.divideByUniqueWordCount` - Penalize repetition
- `.divideByLogUniqueWords` - Divide by (1 + log of unique words)
- `.divideByRankPlusOne` - Normalize to 0-1 range

---

## Highlighting Matches

Show users exactly where matches appear in results:

### Basic Highlighting

```swift
let results = try await db.read { db in
    try await Article
        .where { $0.match("Swift") }
        .select {
            (
                $0.title,
                $0.body.headline(
                    "Swift",
                    startDelimiter: "<mark>",
                    stopDelimiter: "</mark>"
                )
            )
        }
        .fetchAll(db)
}

// Returns: ("Swift Concurrency", "Modern async/await in <mark>Swift</mark>...")
```

### Custom Word Range

Control snippet length using predefined ranges:

```swift
$0.body.headline(
    "Swift",
    startDelimiter: "<mark>",
    stopDelimiter: "</mark>",
    wordRange: .short   // 3-10 words
)

$0.body.headline(
    "Swift",
    startDelimiter: "<mark>",
    stopDelimiter: "</mark>",
    wordRange: .medium  // 10-25 words
)

$0.body.headline(
    "Swift",
    startDelimiter: "<mark>",
    stopDelimiter: "</mark>",
    wordRange: .long    // 20-50 words
)
```

### Custom Range

Define your own word range:

```swift
$0.body.headline(
    "Swift",
    startDelimiter: "<mark>",
    stopDelimiter: "</mark>",
    wordRange: TextSearch.WordRange(min: 15, max: 40)
)
```

### Advanced Options

```swift
$0.body.headline(
    "Swift",
    startDelimiter: "<mark>",
    stopDelimiter: "</mark>",
    wordRange: .medium,
    shortWord: 2,         // Ignore words ≤ 2 chars
    maxFragments: 3       // Show up to 3 text fragments
)
```

---

## Language Support

PostgreSQL supports 20+ languages for stemming and stop words:

### Basic Usage

```swift
// English (default) - stems words
Article.where { $0.match("running", language: "english") }
// Matches: run, runs, running, ran

// Simple - no stemming or stop words
Article.where { $0.match("running", language: "simple") }
// Matches: only "running" exactly

// Other languages
Article.where { $0.match("courir", language: "french") }
Article.where { $0.match("laufen", language: "german") }
Article.where { $0.match("correr", language: "spanish") }
```

### Supported Languages

| Language | Config Name | Language | Config Name |
|----------|-------------|----------|-------------|
| Danish | `danish` | Dutch | `dutch` |
| English | `english` | Finnish | `finnish` |
| French | `french` | German | `german` |
| Hungarian | `hungarian` | Italian | `italian` |
| Norwegian | `norwegian` | Portuguese | `portuguese` |
| Romanian | `romanian` | Russian | `russian` |
| Spanish | `spanish` | Swedish | `swedish` |
| Turkish | `turkish` | Simple | `simple` |

---

## Custom Weighting

Weight different columns differently in your search vector:

### In Trigger Setup

```swift
CREATE OR REPLACE FUNCTION products_search_trigger() RETURNS trigger AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||      -- Title: highest
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') || -- Description: high
    setweight(to_tsvector('english', coalesce(NEW.tags, '')), 'C');          -- Tags: medium
  RETURN NEW;
END
$$ LANGUAGE plpgsql;
```

### Using Database Helpers

```swift
try await db.setupFullTextSearch(
    on: "products",
    weightedColumns: [
        .init(name: "name", weight: .A),         // Highest priority
        .init(name: "description", weight: .B),  // High priority
        .init(name: "tags", weight: .C)          // Medium priority
    ]
)
```

### Impact on Ranking

Weighted columns affect ranking when using `.rank()` with weights:

```swift
Product
    .where { $0.match("laptop") }
    .order {
        $0.rank(
            "laptop",
            weights: [0.0, 0.2, 0.4, 1.0]  // [D, C, B, A]
            // Title matches (A) score 1.0
            // Description matches (B) score 0.4
            // Tag matches (C) score 0.2
            // Other (D) score 0.0
        )
    }
```

---

## Performance Considerations

### Always Use Indexes

Full-text search without an index is extremely slow:

```swift
// ❌ Slow - sequential scan
SELECT * FROM articles WHERE to_tsvector('english', body) @@ to_tsquery('swift');

// ✅ Fast - uses GIN index
SELECT * FROM articles WHERE search_vector @@ to_tsquery('swift');
```

Always create a GIN or GiST index on your tsvector column.

### GIN vs GiST Indexes

| Index Type | Search Speed | Update Speed | Size | Best For |
|------------|--------------|--------------|------|----------|
| **GIN** | Fast | Slow | Large | Static or infrequently updated data |
| **GiST** | Slow | Fast | Small | Frequently updated data |

```swift
// GIN - default, best for most use cases
try await db.createGINIndex(on: "articles", column: "search_vector")

// GiST - for frequently updated tables
try await db.createGiSTIndex(on: "articles", column: "search_vector")
```

**Rule of thumb**: Use GIN unless you're updating search vectors more than once per minute.

### Update Search Vectors Automatically

Always use triggers to keep search vectors in sync:

```swift
// ✅ Good - automatic updates
CREATE TRIGGER articles_search_update
BEFORE INSERT OR UPDATE ON articles
FOR EACH ROW EXECUTE FUNCTION articles_search_trigger();

// ❌ Bad - manual updates required
-- No trigger means search_vector becomes stale
```

### Choose Appropriate Search Method

| Method | Performance | Use Case |
|--------|-------------|----------|
| `match()` | Fast | Full control, sanitized input |
| `plainMatch()` | Fast | User input, simple queries |
| `webMatch()` | Fast | User input, Google-like syntax |
| `phraseMatch()` | Slower | Exact phrases only |

### Consider Normalization Overhead

Ranking with normalization has a small performance cost:

```swift
// Fastest - no normalization
.order { $0.rank("query") }

// Slightly slower - with normalization
.order { $0.rank("query", normalization: .divideByLogLength) }
```

Only use normalization when you need it (usually for better result quality).

---

## Complete Example

Here's a complete, production-ready search service:

```swift
import Records
import StructuredQueriesPostgres
import Dependencies

@Table
struct Article: Codable, Identifiable, FullTextSearchable {
    let id: Int
    var title: String
    var body: String
    var author: String
    var published: Bool
    var createdAt: Date

    static var searchVectorColumn: String { "search_vector" }
}

struct ArticleSearchService {
    @Dependency(\.defaultDatabase) var db

    struct SearchResult {
        let article: Article
        let headline: String
        let rank: Double
    }

    func search(
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> [SearchResult] {
        // Use plainMatch for safe user input
        let results = try await db.read { db in
            try await Article
                .where { $0.published && $0.plainMatch(query) }
                .select {
                    (
                        $0,  // Full article
                        $0.body.headline(
                            query,
                            startDelimiter: "<mark>",
                            stopDelimiter: "</mark>",
                            wordRange: .medium
                        ),
                        $0.rank(
                            query,
                            weights: [0.1, 0.2, 0.4, 1.0],
                            normalization: .divideByLogLength
                        )
                    )
                }
                .order { $0.rank(query, weights: [0.1, 0.2, 0.4, 1.0], normalization: .divideByLogLength) }
                .limit(limit)
                .offset(offset)
                .fetchAll(db)
        }

        return results.map { article, headline, rank in
            SearchResult(article: article, headline: headline, rank: rank)
        }
    }

    func searchByAuthor(
        query: String,
        author: String
    ) async throws -> [SearchResult] {
        let results = try await db.read { db in
            try await Article
                .where { $0.author == author && $0.plainMatch(query) }
                .select {
                    (
                        $0,
                        $0.body.headline(query, startDelimiter: "<mark>", stopDelimiter: "</mark>"),
                        $0.rank(query)
                    )
                }
                .order { $0.rank(query) }
                .fetchAll(db)
        }

        return results.map { article, headline, rank in
            SearchResult(article: article, headline: headline, rank: rank)
        }
    }
}

// Migration
var migrator = Database.Migrator()

migrator.registerMigration("add_articles_fts") { db in
    try await db.setupFullTextSearch(
        on: "articles",
        column: "search_vector",
        weightedColumns: [
            .init(name: "title", weight: .A),
            .init(name: "body", weight: .B),
            .init(name: "author", weight: .C)
        ],
        language: "english",
        indexMethod: .gin
    )
}
```

---

## See Also

- <doc:FullTextSearchQuickReference> - Quick reference for common operations
- <doc:FullTextSearchArchitecture> - Deep-dive into architecture and design decisions
- [PostgreSQL Full-Text Search Documentation](https://www.postgresql.org/docs/current/textsearch.html)
- [Text Search Functions](https://www.postgresql.org/docs/current/functions-textsearch.html)
- [GIN Indexes](https://www.postgresql.org/docs/current/textsearch-indexes.html)
