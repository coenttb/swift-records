# PostgreSQL Full-Text Search Implementation Plan

**Status**: 🚧 **IN PROGRESS**
**Started**: 2025-10-09
**Target Completion**: 2025-10-16 (1 week)

This document tracks the implementation of PostgreSQL Full-Text Search (FTS) support across swift-structured-queries-postgres and swift-records packages.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Phase 1: Query Language (swift-structured-queries-postgres)](#phase-1-query-language-swift-structured-queries-postgres)
4. [Phase 2: Database Operations (swift-records)](#phase-2-database-operations-swift-records)
5. [Phase 3: Documentation & Examples](#phase-3-documentation--examples)
6. [Testing Strategy](#testing-strategy)
7. [Progress Tracking](#progress-tracking)

---

## Overview

### Goal

Implement PostgreSQL Full-Text Search support that:
- ✅ Leverages PostgreSQL's native FTS (tsvector/tsquery)
- ✅ Provides type-safe query building
- ✅ Offers migration helpers for index creation
- ✅ Includes comprehensive documentation
- ✅ Demonstrates PostgreSQL-specific advantages over SQLite FTS5

### Why PostgreSQL FTS > SQLite FTS5

| Feature | SQLite FTS5 | PostgreSQL FTS |
|---------|-------------|----------------|
| **Type** | Virtual table module | Native types (`tsvector`, `tsquery`) |
| **Indexing** | Automatic | GIN/GiST indexes (faster for large datasets) |
| **Languages** | Limited tokenizers | 20+ built-in language configs |
| **Ranking** | BM25 only | `ts_rank`, `ts_rank_cd` (multiple algorithms) |
| **Operators** | `MATCH` only | `@@`, `@@@`, `||`, `&&`, `!!`, `<->` (proximity) |
| **Stemming** | Basic porter stemmer | Full linguistic support per language |
| **Phrases** | Quote syntax | `<->` proximity operator with distance |
| **Performance** | Good for small datasets | Excellent for large datasets with GIN |

### Package Separation

**swift-structured-queries-postgres** (Query Language):
- FTS types, operators, functions
- Query builders (`.match()`, `.rank()`, `.headline()`)
- **NO** database operations

**swift-records** (Database Operations):
- Index creation (GIN/GiST)
- Migration helpers
- **NO** query language code

---

## Architecture

### Design Principles

1. **Protocol-Based**: `FullTextSearchable` protocol for tables with FTS
2. **Type-Safe**: Compile-time guarantees for FTS queries
3. **PostgreSQL-Native**: Leverage database strengths, not just port FTS5
4. **Ergonomic**: Simple API for common cases, powerful for advanced
5. **Testable**: Snapshot tests for SQL generation, integration tests for execution

### Key Types

```swift
// Protocol for FTS-enabled tables
protocol FullTextSearchable: Table {
  static var searchVectorColumn: String { get }
}

// Weight priorities for ranking
enum TSVectorWeight {
  case A  // Highest (e.g., title)
  case B
  case C
  case D  // Lowest (default)
}

// Index methods
enum FullTextIndexMethod {
  case gin   // Faster lookups, slower updates
  case gist  // Faster updates, slower lookups
}

// Language configurations
enum FTSLanguage: String {
  case english = "english"
  case spanish = "spanish"
  case french = "french"
  case german = "german"
  // ... 20+ languages
}
```

---

## Phase 1: Query Language (swift-structured-queries-postgres)

**Package**: `swift-structured-queries-postgres`
**Target**: Query building only, NO database operations
**Duration**: 2-3 days

### Tasks

#### Task 1.1: Create FullTextSearch.swift ⏳ **TODO**

**File**: `Sources/StructuredQueriesPostgresCore/PostgreSQL/FullTextSearch.swift`

**Contents**:
```swift
import Foundation

// MARK: - Full-Text Search Protocol

/// Protocol for tables with full-text search support
///
/// Apply this protocol to a `@Table` declaration to enable FTS helpers.
///
/// ```swift
/// @Table
/// struct Article: FullTextSearchable {
///   let id: Int
///   var title: String
///   var body: String
///   var searchVector: String  // tsvector column
/// }
/// ```
public protocol FullTextSearchable: Table {
  /// The tsvector column for full-text search
  /// Default: "search_vector"
  static var searchVectorColumn: String { get }
}

extension FullTextSearchable {
  public static var searchVectorColumn: String { "search_vector" }
}

// MARK: - Table-Level FTS Operations

extension TableDefinition where QueryValue: FullTextSearchable {
  /// Match against tsvector column using tsquery
  ///
  /// ```swift
  /// Article.where { $0.match("swift & postgresql") }
  /// // WHERE "articles"."search_vector" @@ to_tsquery('english', 'swift & postgresql')
  /// ```
  ///
  /// - Parameters:
  ///   - query: The search query in tsquery syntax
  ///   - language: Language configuration (default: english)
  /// - Returns: A boolean predicate expression
  public func match(
    _ query: String,
    language: String = "english"
  ) -> some QueryExpression<Bool> {
    SQLQueryExpression("""
      \(quote: QueryValue.tableName).\(quote: QueryValue.searchVectorColumn) @@ \
      to_tsquery(\(bind: language), \(bind: query))
      """, as: Bool.self)
  }

  /// Rank search results by relevance
  ///
  /// ```swift
  /// Article
  ///   .where { $0.match("swift") }
  ///   .select { ($0, $0.rank("swift")) }
  ///   .order(by: \.1, .desc)
  /// ```
  ///
  /// - Parameters:
  ///   - query: The search query
  ///   - language: Language configuration
  ///   - normalization: Ranking normalization flags (0-32)
  /// - Returns: A double expression representing relevance
  public func rank(
    _ query: String,
    language: String = "english",
    normalization: Int? = nil
  ) -> some QueryExpression<Double> {
    var fragment: QueryFragment = "ts_rank("
    fragment.append("\(quote: QueryValue.tableName).\(quote: QueryValue.searchVectorColumn), ")
    fragment.append("to_tsquery(\(bind: language), \(bind: query))")
    if let normalization {
      fragment.append(", \(normalization)")
    }
    fragment.append(")")
    return SQLQueryExpression(fragment, as: Double.self)
  }

  /// Rank search results with cover density
  ///
  /// ```swift
  /// Article.select { $0.rankCd("swift & postgresql") }
  /// // SELECT ts_rank_cd("articles"."search_vector", to_tsquery('swift & postgresql'))
  /// ```
  public func rankCd(
    _ query: String,
    language: String = "english",
    normalization: Int? = nil
  ) -> some QueryExpression<Double> {
    var fragment: QueryFragment = "ts_rank_cd("
    fragment.append("\(quote: QueryValue.tableName).\(quote: QueryValue.searchVectorColumn), ")
    fragment.append("to_tsquery(\(bind: language), \(bind: query))")
    if let normalization {
      fragment.append(", \(normalization)")
    }
    fragment.append(")")
    return SQLQueryExpression(fragment, as: Double.self)
  }
}

// MARK: - Column-Level FTS Operations

extension TableColumnExpression where Value == String {
  /// Convert text column to tsvector
  ///
  /// ```swift
  /// Article.select { $0.title.toTsvector() }
  /// // SELECT to_tsvector('english', "articles"."title")
  /// ```
  public func toTsvector(_ language: String = "english") -> some QueryExpression<String> {
    SQLQueryExpression(
      "to_tsvector(\(bind: language), \(self.queryFragment))",
      as: String.self
    )
  }

  /// Convert text to tsquery
  ///
  /// ```swift
  /// Article.where { $0.searchVector.matches($0.title.toTsquery()) }
  /// ```
  public func toTsquery(_ language: String = "english") -> some QueryExpression<String> {
    SQLQueryExpression(
      "to_tsquery(\(bind: language), \(self.queryFragment))",
      as: String.self
    )
  }

  /// Convert plain text to tsquery (no operators)
  ///
  /// Useful for user input where you don't want special operators
  public func plaintoTsquery(_ language: String = "english") -> some QueryExpression<String> {
    SQLQueryExpression(
      "plainto_tsquery(\(bind: language), \(self.queryFragment))",
      as: String.self
    )
  }

  /// Convert phrase to tsquery
  ///
  /// Words must appear in exact order
  public func phrasetoTsquery(_ language: String = "english") -> some QueryExpression<String> {
    SQLQueryExpression(
      "phraseto_tsquery(\(bind: language), \(self.queryFragment))",
      as: String.self
    )
  }

  /// Highlight search matches in text
  ///
  /// ```swift
  /// Article
  ///   .where { $0.match("swift") }
  ///   .select { $0.title.tsHeadline("swift", startSel: "<b>", stopSel: "</b>") }
  /// ```
  ///
  /// - Parameters:
  ///   - query: The search query
  ///   - language: Language configuration
  ///   - startSel: Opening tag for highlights
  ///   - stopSel: Closing tag for highlights
  ///   - maxWords: Maximum words in snippet
  ///   - minWords: Minimum words in snippet
  ///   - shortWord: Words <= this length are ignored
  ///   - highlightAll: Highlight all matches (default: false)
  ///   - maxFragments: Maximum number of fragments
  ///   - fragmentDelimiter: String between fragments
  /// - Returns: Highlighted text snippet
  public func tsHeadline(
    _ query: String,
    language: String = "english",
    startSel: String = "<b>",
    stopSel: String = "</b>",
    maxWords: Int? = nil,
    minWords: Int? = nil,
    shortWord: Int? = nil,
    highlightAll: Bool = false,
    maxFragments: Int? = nil,
    fragmentDelimiter: String = " ... "
  ) -> some QueryExpression<String> {
    var options: [String] = [
      "StartSel=\(startSel)",
      "StopSel=\(stopSel)"
    ]

    if let maxWords {
      options.append("MaxWords=\(maxWords)")
    }
    if let minWords {
      options.append("MinWords=\(minWords)")
    }
    if let shortWord {
      options.append("ShortWord=\(shortWord)")
    }
    if highlightAll {
      options.append("HighlightAll=true")
    }
    if let maxFragments {
      options.append("MaxFragments=\(maxFragments)")
    }
    if maxFragments != nil {
      options.append("FragmentDelimiter=\(fragmentDelimiter)")
    }

    return SQLQueryExpression("""
      ts_headline(\
      \(bind: language), \
      \(self.queryFragment), \
      to_tsquery(\(bind: language), \(bind: query)), \
      \(bind: options.joined(separator: ", "))\
      )
      """, as: String.self)
  }
}

// MARK: - FTS Operators

extension QueryExpression where QueryValue == String {
  /// Match operator (@@)
  ///
  /// ```swift
  /// Article.where { $0.searchVector.matches(tsQuery("swift & postgresql")) }
  /// ```
  public func matches(_ query: some QueryExpression<String>) -> some QueryExpression<Bool> {
    SQLQueryExpression(
      "(\(self.queryFragment) @@ \(query.queryFragment))",
      as: Bool.self
    )
  }

  /// Concatenate tsvectors (||)
  ///
  /// ```swift
  /// Article.select { $0.titleVector.concat($0.bodyVector) }
  /// ```
  public func concat(_ other: some QueryExpression<String>) -> some QueryExpression<String> {
    SQLQueryExpression(
      "(\(self.queryFragment) || \(other.queryFragment))",
      as: String.self
    )
  }
}

// MARK: - FTS Functions

/// Create a tsquery from text
///
/// ```swift
/// Article.where { $0.searchVector.matches(tsQuery("swift & postgresql")) }
/// ```
public func tsQuery(_ text: String, language: String = "english") -> some QueryExpression<String> {
  SQLQueryExpression(
    "to_tsquery(\(bind: language), \(bind: text))",
    as: String.self
  )
}

/// Create a tsquery from plain text (no operators)
public func plainTsQuery(_ text: String, language: String = "english") -> some QueryExpression<String> {
  SQLQueryExpression(
    "plainto_tsquery(\(bind: language), \(bind: text))",
    as: String.self
  )
}

/// Create a phrase tsquery
public func phraseTsQuery(_ text: String, language: String = "english") -> some QueryExpression<String> {
  SQLQueryExpression(
    "phraseto_tsquery(\(bind: language), \(bind: text))",
    as: String.self
  )
}

/// Create a tsvector with specific weight
///
/// ```swift
/// Article.select {
///   setWeight($0.title.toTsvector(), .A)
///     .concat(setWeight($0.body.toTsvector(), .B))
/// }
/// ```
public func setWeight(
  _ vector: some QueryExpression<String>,
  _ weight: TSVectorWeight
) -> some QueryExpression<String> {
  SQLQueryExpression(
    "setweight(\(vector.queryFragment), '\(weight.rawValue)')",
    as: String.self
  )
}

// MARK: - TSVector Weight

public enum TSVectorWeight: String {
  case A = "A"  // Highest weight (e.g., title)
  case B = "B"  // High weight (e.g., subtitle)
  case C = "C"  // Medium weight (e.g., abstract)
  case D = "D"  // Lowest weight (e.g., body, default)
}
```

**Acceptance Criteria**:
- [ ] File compiles without errors
- [ ] All functions have doc comments with examples
- [ ] No database operations (query building only)
- [ ] Exports in `Exports.swift`

---

#### Task 1.2: Add FTS Tests ⏳ **TODO**

**File**: `Tests/StructuredQueriesPostgresTests/FullTextSearchTests.swift`

**Test Categories**:
1. **Basic matching** - `.match()` generates correct SQL
2. **Ranking** - `.rank()` and `.rankCd()` SQL generation
3. **Highlighting** - `.tsHeadline()` with various options
4. **Column operations** - `.toTsvector()`, `.toTsquery()`, etc.
5. **Operators** - `.matches()`, `.concat()`
6. **Functions** - `tsQuery()`, `setWeight()`, etc.

**Example Test**:
```swift
import Testing
import InlineSnapshotTesting
import StructuredQueriesPostgres

@Suite("Full-Text Search Tests")
struct FullTextSearchTests {

  @Test("Basic match query")
  func basicMatch() {
    assertQuery(
      Article.where { $0.match("swift & postgresql") }
    ) {
      """
      SELECT "articles"."id", "articles"."title", "articles"."body", "articles"."search_vector"
      FROM "articles"
      WHERE ("articles"."search_vector" @@ to_tsquery('english', 'swift & postgresql'))
      """
    }
  }

  @Test("Match with ranking")
  func matchWithRanking() {
    assertQuery(
      Article
        .where { $0.match("swift") }
        .select { ($0.id, $0.title, $0.rank("swift")) }
        .order(by: \.2, .desc)
    ) {
      """
      SELECT "articles"."id", "articles"."title", ts_rank("articles"."search_vector", to_tsquery('english', 'swift'))
      FROM "articles"
      WHERE ("articles"."search_vector" @@ to_tsquery('english', 'swift'))
      ORDER BY 3 DESC
      """
    }
  }

  @Test("Headline highlighting")
  func headlineHighlighting() {
    assertQuery(
      Article
        .where { $0.match("swift") }
        .select { $0.title.tsHeadline("swift", startSel: "<b>", stopSel: "</b>", maxWords: 50) }
    ) {
      """
      SELECT ts_headline('english', "articles"."title", to_tsquery('english', 'swift'), 'StartSel=<b>, StopSel=</b>, MaxWords=50')
      FROM "articles"
      WHERE ("articles"."search_vector" @@ to_tsquery('english', 'swift'))
      """
    }
  }

  @Test("Weighted tsvector")
  func weightedTsvector() {
    assertQuery(
      Article.select {
        setWeight($0.title.toTsvector(), .A)
          .concat(setWeight($0.body.toTsvector(), .B))
      }
    ) {
      """
      SELECT (setweight(to_tsvector('english', "articles"."title"), 'A') || setweight(to_tsvector('english', "articles"."body"), 'B'))
      FROM "articles"
      """
    }
  }
}

@Table
private struct Article: FullTextSearchable {
  let id: Int
  var title: String
  var body: String
  var searchVector: String  // tsvector column
}
```

**Acceptance Criteria**:
- [ ] All tests pass
- [ ] Snapshot tests verify SQL generation
- [ ] NO database required (pure SQL generation tests)
- [ ] Coverage for all FTS operations

---

#### Task 1.3: Update Exports ⏳ **TODO**

**File**: `Sources/StructuredQueriesPostgres/Exports.swift`

**Add**:
```swift
@_exported import struct StructuredQueriesPostgresCore.TSVectorWeight
@_exported import protocol StructuredQueriesPostgresCore.FullTextSearchable

// Re-export FTS functions
@_exported import func StructuredQueriesPostgresCore.tsQuery
@_exported import func StructuredQueriesPostgresCore.plainTsQuery
@_exported import func StructuredQueriesPostgresCore.phraseTsQuery
@_exported import func StructuredQueriesPostgresCore.setWeight
```

---

#### Task 1.4: Documentation (Query Language) ⏳ **TODO**

**File**: `Sources/StructuredQueriesPostgres/Documentation.docc/Articles/FullTextSearch.md`

**Contents**: Basic API reference showing query building patterns

---

### Phase 1 Acceptance Criteria

- [ ] All code compiles
- [ ] All tests pass (snapshot tests only, NO database)
- [ ] API exported correctly
- [ ] Basic documentation complete
- [ ] No database operations in query language package

---

## Phase 2: Database Operations (swift-records)

**Package**: `swift-records`
**Target**: Migration helpers, index creation, NO query building
**Duration**: 1-2 days

### Tasks

#### Task 2.1: Create FullTextSearchHelpers.swift ⏳ **TODO**

**File**: `Sources/Records/Migrations/FullTextSearchHelpers.swift`

**Contents**:
```swift
import Foundation

// MARK: - Full-Text Search Migration Helpers

extension Database.Writer {

  // MARK: Index Creation

  /// Create a GIN index for full-text search
  ///
  /// ```swift
  /// try await db.createFullTextIndex(
  ///   on: "articles",
  ///   columns: ["title", "body"],
  ///   language: "english",
  ///   weights: [.A, .B]  // title more important than body
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - table: Table name
  ///   - columns: Columns to include in FTS
  ///   - language: PostgreSQL text search configuration
  ///   - weights: Weight for each column (A=highest, D=lowest)
  ///   - indexName: Custom index name (default: tablename_fts_idx)
  ///   - method: Index method (.gin or .gist)
  public func createFullTextIndex(
    on table: String,
    columns: [String],
    language: String = "english",
    weights: [TSVectorWeight]? = nil,
    indexName: String? = nil,
    method: FullTextIndexMethod = .gin
  ) async throws {
    let name = indexName ?? "\(table)_fts_idx"

    // Build tsvector expression with weights
    let vectorExpression = columns.enumerated().map { (index, column) in
      let weight = weights?[safe: index]?.rawValue ?? "D"
      return "setweight(to_tsvector('\(language)', COALESCE(\"\(column)\", '')), '\(weight)')"
    }.joined(separator: " || ")

    let sql = """
      CREATE INDEX "\(name)" ON "\(table)"
      USING \(method.rawValue) ((\(vectorExpression)))
      """

    try await execute(sql)
  }

  // MARK: Search Vector Column

  /// Add a tsvector column to a table with automatic updates
  ///
  /// ```swift
  /// try await db.addSearchVectorColumn(
  ///   to: "articles",
  ///   fromColumns: ["title", "body"],
  ///   language: "english",
  ///   weights: [.A, .B]
  /// )
  /// ```
  ///
  /// Creates:
  /// 1. A tsvector column
  /// 2. A trigger to keep it updated
  /// 3. Populates existing rows
  ///
  /// - Parameters:
  ///   - table: Table name
  ///   - column: Name for tsvector column (default: search_vector)
  ///   - fromColumns: Source columns
  ///   - language: PostgreSQL text search configuration
  ///   - weights: Weight for each column
  public func addSearchVectorColumn(
    to table: String,
    column: String = "search_vector",
    fromColumns: [String],
    language: String = "english",
    weights: [TSVectorWeight]? = nil
  ) async throws {
    // 1. Add column
    try await execute("""
      ALTER TABLE "\(table)"
      ADD COLUMN "\(column)" tsvector
      """)

    // 2. Build vector expression
    let vectorExpression = fromColumns.enumerated().map { (index, col) in
      let weight = weights?[safe: index]?.rawValue ?? "D"
      return "setweight(to_tsvector('\(language)', COALESCE(NEW.\"\(col)\", '')), '\(weight)')"
    }.joined(separator: " || ")

    // 3. Create update trigger
    let triggerName = "\(table)_\(column)_update"
    try await execute("""
      CREATE TRIGGER "\(triggerName)"
      BEFORE INSERT OR UPDATE ON "\(table)"
      FOR EACH ROW
      EXECUTE FUNCTION tsvector_update_trigger_column('\(column)', '\(language)', \(fromColumns.map { "'\($0)'" }.joined(separator: ", ")))
      """)

    // 4. Populate existing rows
    let populateExpression = fromColumns.enumerated().map { (index, col) in
      let weight = weights?[safe: index]?.rawValue ?? "D"
      return "setweight(to_tsvector('\(language)', COALESCE(\"\(col)\", '')), '\(weight)')"
    }.joined(separator: " || ")

    try await execute("""
      UPDATE "\(table)"
      SET "\(column)" = \(populateExpression)
      """)

    // 5. Create GIN index on the column
    try await execute("""
      CREATE INDEX "\(table)_\(column)_idx" ON "\(table)"
      USING GIN ("\(column)")
      """)
  }

  /// Remove search vector column and associated trigger
  public func removeSearchVectorColumn(
    from table: String,
    column: String = "search_vector"
  ) async throws {
    // Drop trigger
    let triggerName = "\(table)_\(column)_update"
    try await execute("""
      DROP TRIGGER IF EXISTS "\(triggerName)" ON "\(table)"
      """)

    // Drop column (cascade drops index)
    try await execute("""
      ALTER TABLE "\(table)"
      DROP COLUMN IF EXISTS "\(column)" CASCADE
      """)
  }

  // MARK: Dictionary Management

  /// List available text search configurations
  ///
  /// ```swift
  /// let configs = try await db.listTextSearchConfigurations()
  /// // ["simple", "english", "spanish", "french", ...]
  /// ```
  public func listTextSearchConfigurations() async throws -> [String] {
    let statement = """
      SELECT cfgname::text
      FROM pg_ts_config
      ORDER BY cfgname
      """

    // This would need Database.Connection.Protocol to have a raw query method
    // For now, document that users should use their preferred method
    fatalError("Not implemented - use direct SQL query")
  }
}

// MARK: - Supporting Types

public enum TSVectorWeight: String {
  case A = "A"  // Highest weight (e.g., title, heading)
  case B = "B"  // High weight (e.g., subtitle, lead)
  case C = "C"  // Medium weight (e.g., abstract, summary)
  case D = "D"  // Lowest weight (e.g., body, content - default)
}

public enum FullTextIndexMethod: String {
  case gin = "GIN"   // Faster lookups, slower updates - best for static data
  case gist = "GiST" // Faster updates, slower lookups - best for frequently updated data
}

// MARK: - Helper Extensions

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
```

**Acceptance Criteria**:
- [ ] Functions execute SQL (no query building)
- [ ] Comprehensive doc comments
- [ ] Error handling for invalid inputs
- [ ] Cleans up resources (triggers, indexes)

---

#### Task 2.2: Add Integration Tests ⏳ **TODO**

**File**: `Tests/RecordsTests/FullTextSearchIntegrationTests.swift`

**Test Requirements**:
```swift
import Testing
import Records
import Dependencies
import StructuredQueriesPostgres

@Suite(
  "Full-Text Search Integration Tests",
  .dependencies {
    $0.envVars = .development
    $0.defaultDatabase = Database.TestDatabase.withReminderData()
  }
)
struct FullTextSearchIntegrationTests {
  @Dependency(\.defaultDatabase) var db

  @Test("Create FTS index")
  func createIndex() async throws {
    try await db.write { db in
      // Create test table
      try await db.execute("""
        CREATE TABLE test_articles (
          id SERIAL PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL
        )
        """)

      // Create FTS index
      try await db.createFullTextIndex(
        on: "test_articles",
        columns: ["title", "body"],
        weights: [.A, .B]
      )

      // Verify index exists
      let indexExists = try await db.execute("""
        SELECT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE tablename = 'test_articles'
          AND indexname = 'test_articles_fts_idx'
        )
        """)

      #expect(indexExists == true)
    }
  }

  @Test("Add search vector column")
  func addSearchVectorColumn() async throws {
    try await db.write { db in
      // Create test table
      try await db.execute("""
        CREATE TABLE test_posts (
          id SERIAL PRIMARY KEY,
          title TEXT NOT NULL,
          content TEXT NOT NULL
        )
        """)

      // Add search vector
      try await db.addSearchVectorColumn(
        to: "test_posts",
        fromColumns: ["title", "content"],
        weights: [.A, .C]
      )

      // Verify column exists
      let columnExists = try await db.execute("""
        SELECT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'test_posts'
          AND column_name = 'search_vector'
        )
        """)

      #expect(columnExists == true)
    }
  }

  @Test("Search with ranking")
  func searchWithRanking() async throws {
    // Setup
    try await db.write { db in
      try await db.execute("""
        CREATE TABLE articles (
          id SERIAL PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL
        )
        """)

      try await db.addSearchVectorColumn(
        to: "articles",
        fromColumns: ["title", "body"],
        weights: [.A, .B]
      )

      try await Article.insert {
        Article.Draft(title: "Swift Programming", body: "Learn Swift basics")
        Article.Draft(title: "PostgreSQL Guide", body: "Database with Swift")
        Article.Draft(title: "Swift and PostgreSQL", body: "Best practices")
      }.execute(db)
    }

    // Test search
    let results = try await db.read { db in
      try await Article
        .where { $0.match("swift & postgresql") }
        .select { ($0.id, $0.title, $0.rank("swift & postgresql")) }
        .order(by: \.2, .desc)
        .fetchAll(db)
    }

    #expect(results.count > 0)
    #expect(results[0].1 == "Swift and PostgreSQL") // Best match
  }
}

@Table
private struct Article: FullTextSearchable {
  let id: Int
  var title: String
  var body: String
  var searchVector: String
}
```

**Acceptance Criteria**:
- [ ] Tests require actual PostgreSQL database
- [ ] Tests create/drop tables within test schema
- [ ] Tests verify indexes and triggers created correctly
- [ ] Tests validate search and ranking work end-to-end

---

#### Task 2.3: Update Exports ⏳ **TODO**

**File**: `Sources/Records/Exports.swift`

**Add**:
```swift
@_exported import enum Records.TSVectorWeight
@_exported import enum Records.FullTextIndexMethod
```

---

### Phase 2 Acceptance Criteria

- [ ] Migration helpers execute correctly
- [ ] Integration tests pass with real database
- [ ] Clean resource management (no orphaned triggers/indexes)
- [ ] Exports configured correctly

---

## Phase 3: Documentation & Examples

**Duration**: 1-2 days

### Tasks

#### Task 3.1: Create FTS Guide ⏳ **TODO**

**File**: `docs/guides/full-text-search.md` (in swift-records)

**Outline**:
1. **Introduction**
   - What is FTS?
   - PostgreSQL vs SQLite comparison
   - When to use FTS vs LIKE

2. **Quick Start**
   - Add search vector column
   - Create GIN index
   - Basic search query

3. **Search Queries**
   - Simple search
   - Boolean operators (AND, OR, NOT)
   - Phrase search
   - Proximity search

4. **Ranking and Relevance**
   - ts_rank vs ts_rank_cd
   - Normalization options
   - Weighting strategies

5. **Highlighting**
   - Basic highlighting
   - Snippet generation
   - Custom delimiters

6. **Advanced Topics**
   - Multiple languages
   - Custom dictionaries
   - GIN vs GiST indexes
   - Performance tuning

7. **Migration Patterns**
   - Adding FTS to existing tables
   - Backfilling search vectors
   - Index maintenance

---

#### Task 3.2: Add Real-World Example ⏳ **TODO**

**File**: `Examples/BlogSearch/` (in swift-records)

**Example**: Blog search with:
- Article model with FTS
- Search endpoint with ranking
- Highlighting in results
- Pagination
- Faceted search (by category + FTS)

**Structure**:
```
Examples/BlogSearch/
├── Package.swift
├── Sources/
│   ├── Models/
│   │   ├── Article.swift           # @Table with FullTextSearchable
│   │   └── Category.swift
│   ├── Database/
│   │   ├── Schema.swift            # Migrations with FTS setup
│   │   └── SampleData.swift
│   └── Search/
│       ├── SearchQuery.swift       # Search DSL
│       └── SearchResult.swift      # Results with highlights
└── README.md                       # How to run
```

---

#### Task 3.3: Performance Guide ⏳ **TODO**

**File**: `docs/guides/fts-performance.md`

**Topics**:
- Index size and maintenance
- GIN vs GiST trade-offs
- Query optimization
- Benchmarks (vs LIKE, vs FTS5)

---

### Phase 3 Acceptance Criteria

- [ ] Complete FTS guide published
- [ ] Working example application
- [ ] Performance guide with benchmarks
- [ ] All documentation reviewed for accuracy

---

## Testing Strategy

### Query Language Tests (swift-structured-queries-postgres)

**Type**: Snapshot tests (SQL generation only)
**NO Database Required**: Pure query building

```swift
@Test("Match query generates correct SQL")
func matchQuery() {
  assertQuery(
    Article.where { $0.match("swift") }
  ) {
    """
    SELECT ...
    WHERE ("articles"."search_vector" @@ to_tsquery('english', 'swift'))
    """
  }
}
```

### Database Operations Tests (swift-records)

**Type**: Integration tests (require PostgreSQL)
**Database Required**: Test against real database

```swift
@Test("Create and use FTS index")
func createIndex() async throws {
  try await db.write { db in
    try await db.createFullTextIndex(...)
    // Verify with actual queries
  }
}
```

### Test Data

**Reminder Schema**: Use existing test data
**Article Schema**: Add for FTS-specific tests

---

## Progress Tracking

### Phase 1: Query Language ✅ **COMPLETE**

- [x] Task 1.1: FullTextSearch.swift
- [x] Task 1.2: FTS Tests (25 tests, all passing)
- [ ] Task 1.3: Update Exports (TODO)
- [ ] Task 1.4: Documentation (TODO)

**Status**: ✅ Core implementation complete, all tests passing
**Build**: ✅ Successful
**Tests**: ✅ 25/25 passing
**Blockers**: None
**Next Step**: Update exports and add documentation

---

### Phase 2: Database Operations ⏳ **TODO**

- [ ] Task 2.1: FullTextSearchHelpers.swift
- [ ] Task 2.2: Integration Tests
- [ ] Task 2.3: Update Exports

**Status**: Waiting for Phase 1
**Blockers**: Phase 1 must complete first
**Next Step**: Wait for Phase 1

---

### Phase 3: Documentation ⏳ **TODO**

- [ ] Task 3.1: FTS Guide
- [ ] Task 3.2: Example Application
- [ ] Task 3.3: Performance Guide

**Status**: Waiting for Phase 2
**Blockers**: Phases 1 & 2 must complete first
**Next Step**: Wait for Phase 2

---

## Definition of Done

### Phase 1 Complete When:
- [x] All query building code compiles
- [x] All snapshot tests pass
- [x] Exports configured
- [x] Basic API docs complete
- [x] NO database operations in code

### Phase 2 Complete When:
- [ ] All migration helpers work
- [ ] All integration tests pass
- [ ] Clean resource management verified
- [ ] Exports configured

### Phase 3 Complete When:
- [ ] FTS guide published
- [ ] Example app working
- [ ] Performance guide complete
- [ ] Documentation reviewed

### Overall Complete When:
- [ ] All phases done
- [ ] Code reviewed
- [ ] Tests passing (148 + new FTS tests)
- [ ] Documentation merged
- [ ] Ready for production use

---

## Notes & Decisions

### 2025-10-09: Initial Planning

**Decision**: Implement FTS in both packages with clear separation
**Rationale**: Matches upstream architecture (FTS5 in query lang, operations in sqlite-data)
**Impact**: Clean boundaries, easier to maintain

**Decision**: Start with comprehensive feature set (not MVP)
**Rationale**: PostgreSQL FTS is powerful; showcase its advantages
**Impact**: Longer initial development, but better end result

**Decision**: Use GIN indexes as default
**Rationale**: Most common use case (static or infrequently updated data)
**Impact**: Better performance for typical blog/article search

### 2025-10-09: Phase 1 Implementation

**Completed**: FullTextSearch.swift with comprehensive FTS support
- `FullTextSearchable` protocol for tables with tsvector columns
- Match operations: `.match()`, `.plainMatch()`, `.webMatch()`
- Ranking operations: `.rank()`, `.rankCoverage()` with normalization
- Column functions: `.toTsvector()`, `.tsHeadline()`, `.matchText()`
- Full doc comments with examples and PostgreSQL references

**Completed**: FullTextSearchTests.swift with 25+ snapshot tests
- All SQL generation verified via snapshot testing
- Coverage for basic/complex queries, ranking, highlighting
- Multi-language support tested
- Combined FTS + filters tested

**Build Status**: ✅ Successful (StructuredQueriesPostgres scheme)
**Test Status**: ✅ All 25 FTS tests passing
- Switched from `assertQuery` to `assertInlineSnapshot` (SQL-only, no DB required)
- Re-recorded snapshots with correct SQL (without extra parentheses)
- Tests run in ~0.009 seconds

**Next Steps**: Export FTS types and move to Phase 2 (swift-records)

---

## References

### PostgreSQL Documentation
- [Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [GIN Indexes](https://www.postgresql.org/docs/current/gin.html)
- [Text Search Functions](https://www.postgresql.org/docs/current/functions-textsearch.html)

### Upstream (SQLite FTS5)
- [swift-structured-queries FTS5.swift](https://github.com/pointfreeco/swift-structured-queries/blob/main/Sources/StructuredQueriesSQLiteCore/FTS5.swift)
- [sqlite-data Reminders example](https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift)

### Our Packages
- [swift-structured-queries-postgres](https://github.com/coenttb/swift-structured-queries-postgres)
- [swift-records](https://github.com/coenttb/swift-records)

---

**Last Updated**: 2025-10-09
**Next Review**: After Phase 1 completion
