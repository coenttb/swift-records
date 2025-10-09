# swift-records Deduplication Plan

**Date**: 2025-10-08
**Issue**: Ambiguous function errors due to duplicate query language code in swift-records conflicting with restored upstream code in swift-structured-queries-postgres

## Problem Summary

When swift-structured-queries-postgres was initially forked, aggregate and scalar functions were removed. swift-records filled this gap by duplicating ~500 lines of query language code. After restoring upstream functionality, both packages now contain identical extensions, causing build failures.

## Architecture Principle

**swift-structured-queries-postgres** (Query Language Layer):
- Builds SQL queries, returns `Statement<QueryValue>` types
- NO database connections or execution
- Includes: Query DSL, aggregate functions, scalar functions, PostgreSQL-specific SQL syntax
- Example: `User.find([1,2,3])`, `User.select { $0.name }`

**swift-records** (Database Operations Layer):
- Executes queries via `.execute(db)`, `.fetchAll(db)`, `.fetchOne(db)`
- Connection pooling, transactions, migrations
- Should NOT duplicate query building functionality
- Example: `try await User.find([1,2,3]).fetchAll(db)`

## Audit Results

### Files in swift-records/Sources/Records/Extensions/

#### 1. QueryExpression.swift (17KB, ~513 lines)

**DUPLICATES - REMOVE**:
- Lines 11-40: `count()` aggregate → Duplicate of `AggregateFunctions.swift:19-29`
- Lines 44-74: `max()`, `min()` aggregates → Duplicate of `AggregateFunctions.swift:87-116`
- Lines 76-127: `avg()`, `sum()` aggregates → Duplicate of `AggregateFunctions.swift:119-167`
- Lines 129-144: `count(*)` static method → Duplicate of `AggregateFunctions.swift:194-208`
- Lines 146-183: `AggregateFunction` struct → Duplicate of `AggregateFunctions.swift:212-248`
- Lines 226-241: `length()` → Duplicate of `ScalarFunctions.swift`
- Lines 243-265: `round()` → Duplicate of `ScalarFunctions.swift`
- Lines 267-282: `abs()`, `sign()` → Duplicate of `ScalarFunctions.swift`
- Lines 286-360: Coalesce `??` operators → Duplicate of `ScalarFunctions.swift`
- Lines 364-371: `lower()` → Duplicate of `ScalarFunctions.swift`
- Lines 373-394: `ltrim()`, `octetLength()` → Duplicate of `ScalarFunctions.swift`
- Lines 398-467: `replace()`, `rtrim()`, `substr()`, `trim()`, `upper()` → Duplicate of `ScalarFunctions.swift`
- Lines 471-483: `QueryFunction` struct → Duplicate of `ScalarFunctions.swift`
- Lines 485-513: `CoalesceFunction` struct → Duplicate of `ScalarFunctions.swift`

**POSTGRESQL-SPECIFIC - MOVE TO swift-structured-queries-postgres**:
- Lines 185-224: `ilike()` extension and `IlikeOperator` struct
  - PostgreSQL's case-insensitive LIKE operator
  - Belongs in `swift-structured-queries-postgres/Sources/PostgreSQL/PostgreSQLFunctions.swift`

**ACTION**: Delete entire file after moving `ilike()` to swift-structured-queries-postgres

#### 2. PrimaryKeyedTableDefinition.swift (~26 lines)

**DUPLICATE - REMOVE**:
- Entire file duplicates extension already in `swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/PrimaryKeyed.swift:71-85`
- swift-records version is missing `where PrimaryColumn: TableColumnExpression` constraint
- Creates ambiguity when calling `primaryKey.count()`

**ACTION**: Delete entire file

#### 3. Collation.swift (~28 lines)

**LEGITIMATE - KEEP**:
- Convenience constants for PostgreSQL collations (`.c`, `.posix`, `.enUS`, etc.)
- Not query building, just constant definitions
- Appropriate for database operations layer

**ACTION**: Keep in swift-records

#### 4. Select.swift (~65 lines)

**VERIFIED IN UPSTREAM - REMOVE**:
- Adds `.count()` methods to Select statements
- Upstream `swift-structured-queries/Sources/StructuredQueriesCore/Statements/Select.swift` has this at lines 292 and 1627
- These are query building extensions

**ACTION**: Delete entire file (already in upstream)

#### 5. Table.swift (~21 lines)

**NOT IN UPSTREAM - EVALUATE**:
- Adds static `.count()` method to Table protocol
- Convenient shorthand for creating count queries
- Not found in upstream swift-structured-queries
- Query building extension (belongs in swift-structured-queries-postgres)

**ACTION**:
- Option A: Move to swift-structured-queries-postgres (recommended - it's query language)
- Option B: Delete if not essential

**DECISION**: Move to swift-structured-queries-postgres as it's a useful query building convenience

#### 6. TableColumn.swift (~100 lines)

**POSTGRESQL-SPECIFIC AGGREGATES - MOVE TO swift-structured-queries-postgres**:
- Lines 6-39: PostgreSQL aggregate functions
  - `string_agg()` (equivalent to SQLite's `group_concat`)
  - `array_agg()` (PostgreSQL-only)
  - `json_agg()` (PostgreSQL-only)
  - `jsonb_agg()` (PostgreSQL-only)
- Lines 43-75: PostgreSQL statistical functions
  - `stddev()`, `stddev_pop()`, `stddev_samp()`, `variance()`
- Lines 79-99: `SimpleAggregateFunction` helper struct

**ACTION**:
- Move to `swift-structured-queries-postgres/Sources/PostgreSQL/PostgreSQLAggregates.swift` (new file)
- These are query language features, not database operations

#### 7. Where.swift (~23 lines)

**VERIFIED IN UPSTREAM - REMOVE**:
- Adds `.count()` method to Where statements
- Upstream `swift-structured-queries/Sources/StructuredQueriesCore/Statements/Where.swift` has this at line 484
- Query building extension

**ACTION**: Delete entire file (already in upstream)

## Implementation Plan

### Phase 1: Create PostgreSQL-Specific Files in swift-structured-queries-postgres

#### 1.1 Add ilike() to PostgreSQLFunctions.swift

File: `/Users/coen/Developer/coenttb/swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/PostgreSQL/PostgreSQLFunctions.swift`

Add at end of file:

```swift
// MARK: - PostgreSQL ILIKE Operator

extension QueryExpression where QueryValue == String {
    /// A predicate expression from this string expression matched against another via the `ILIKE`
    /// operator (case-insensitive LIKE in PostgreSQL).
    ///
    /// ```swift
    /// Reminder.where { $0.title.ilike("%GET%") }
    /// // SELECT … FROM "reminders" WHERE ("reminders"."title" ILIKE '%GET%')
    /// ```
    ///
    /// - Parameters:
    ///   - pattern: A string expression describing the `ILIKE` pattern.
    ///   - escape: An optional character for the `ESCAPE` clause.
    /// - Returns: A predicate expression.
    public func ilike(
        _ pattern: some StringProtocol,
        escape: Character? = nil
    ) -> some QueryExpression<Bool> {
        IlikeOperator(string: self, pattern: "\(pattern)", escape: escape)
    }
}

private struct IlikeOperator<
    LHS: QueryExpression<String>,
    RHS: QueryExpression<String>
>: QueryExpression {
    typealias QueryValue = Bool

    let string: LHS
    let pattern: RHS
    let escape: Character?

    var queryFragment: QueryFragment {
        var query: QueryFragment = "(\(string.queryFragment) ILIKE \(pattern.queryFragment)"
        if let escape {
            query.append(" ESCAPE \(bind: String(escape))")
        }
        query.append(")")
        return query
    }
}
```

#### 1.2 Create PostgreSQLAggregates.swift

File: `/Users/coen/Developer/coenttb/swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/PostgreSQL/PostgreSQLAggregates.swift`

```swift
import Foundation

// MARK: - PostgreSQL-specific Aggregate Functions

extension TableColumn {
    /// PostgreSQL STRING_AGG function - concatenates strings with a separator
    /// Equivalent to SQLite's GROUP_CONCAT
    public func stringAgg(_ separator: String) -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "string_agg",
            column: queryFragment,
            separator: separator.queryFragment
        )
    }

    /// PostgreSQL ARRAY_AGG function - aggregates values into an array
    public func arrayAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "array_agg",
            column: queryFragment
        )
    }

    /// PostgreSQL JSON_AGG function - aggregates values into a JSON array
    public func jsonAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "json_agg",
            column: queryFragment
        )
    }

    /// PostgreSQL JSONB_AGG function - aggregates values into a JSONB array
    public func jsonbAgg() -> some QueryExpression<String?> {
        SimpleAggregateFunction<String?>(
            name: "jsonb_agg",
            column: queryFragment
        )
    }
}

// MARK: - Statistical Functions

extension TableColumn where Value: Numeric {
    /// PostgreSQL STDDEV function - standard deviation
    public func stddev() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev",
            column: queryFragment
        )
    }

    /// PostgreSQL STDDEV_POP function - population standard deviation
    public func stddevPop() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev_pop",
            column: queryFragment
        )
    }

    /// PostgreSQL STDDEV_SAMP function - sample standard deviation
    public func stddevSamp() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "stddev_samp",
            column: queryFragment
        )
    }

    /// PostgreSQL VARIANCE function - variance
    public func variance() -> some QueryExpression<Double> {
        SimpleAggregateFunction<Double>(
            name: "variance",
            column: queryFragment
        )
    }
}

// MARK: - Simple aggregate function helper

private struct SimpleAggregateFunction<QueryValue: QueryBindable>: QueryExpression {
    let name: String
    let column: QueryFragment
    let separator: QueryFragment?

    init(name: String, column: QueryFragment, separator: QueryFragment? = nil) {
        self.name = name
        self.column = column
        self.separator = separator
    }

    var queryFragment: QueryFragment {
        if let separator = separator {
            // For functions like string_agg that take two arguments
            return "\(QueryFragment(stringLiteral: name))(\(column), \(separator))"
        } else {
            // For single-argument aggregate functions
            return "\(QueryFragment(stringLiteral: name))(\(column))"
        }
    }
}
```

#### 1.3 Add Table.count() convenience method

File: `/Users/coen/Developer/coenttb/swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/Table.swift`

Add at end of file:

```swift
extension Table {
    /// A select statement for this table's row count.
    ///
    /// ```swift
    /// Reminder.count()
    /// // SELECT count(*) FROM "reminders"
    /// ```
    ///
    /// - Parameter filter: A `FILTER` clause to apply to the aggregation.
    /// - Returns: A select statement that selects `count(*)`.
    public static func count(
        filter: ((TableColumns) -> any QueryExpression<Bool>)? = nil
    ) -> Select<Int, Self, ()> {
        Where().count(filter: filter)
    }
}
```

### Phase 2: Delete Duplicate Files from swift-records

Remove these files entirely:
- `swift-records/Sources/Records/Extensions/QueryExpression.swift`
- `swift-records/Sources/Records/Extensions/PrimaryKeyedTableDefinition.swift`
- `swift-records/Sources/Records/Extensions/Select.swift`
- `swift-records/Sources/Records/Extensions/Table.swift`
- `swift-records/Sources/Records/Extensions/TableColumn.swift`
- `swift-records/Sources/Records/Extensions/Where.swift`

Keep these files:
- `swift-records/Sources/Records/Extensions/Collation.swift` (legitimate database operations constants)

### Phase 3: Build and Test

#### 3.1 Build swift-structured-queries-postgres

```bash
xcodebuild -workspace /Users/coen/Developer/coenttb/StructuredQueries.xcworkspace \
  -scheme swift-structured-queries-postgres \
  -destination 'platform=macOS' build
```

Expected: Success

#### 3.2 Build swift-records

```bash
xcodebuild -workspace /Users/coen/Developer/coenttb/StructuredQueries.xcworkspace \
  -scheme Records \
  -destination 'platform=macOS' build
```

Expected: Success (no more ambiguity errors)

#### 3.3 Run Tests

```bash
xcodebuild -workspace /Users/coen/Developer/coenttb/StructuredQueries.xcworkspace \
  -scheme swift-structured-queries-postgres \
  -destination 'platform=macOS' test

xcodebuild -workspace /Users/coen/Developer/coenttb/StructuredQueries.xcworkspace \
  -scheme Records \
  -destination 'platform=macOS' test
```

### Phase 4: Update Documentation

#### 4.1 Update swift-structured-queries-postgres/CLAUDE.md

Add to "PostgreSQL-Specific Functions" section:

```markdown
4. **PostgreSQL-Specific Aggregates** (PostgreSQL/PostgreSQLAggregates.swift)
   - String aggregation: `string_agg()` (equivalent to SQLite's `group_concat`)
   - Array aggregation: `array_agg()`
   - JSON aggregation: `json_agg()`, `jsonb_agg()`
   - Statistical: `stddev()`, `stddev_pop()`, `stddev_samp()`, `variance()`

5. **PostgreSQL String Operators** (PostgreSQL/PostgreSQLFunctions.swift)
   - Case-insensitive matching: `ilike()` operator
```

#### 4.2 Update swift-records/CLAUDE.md

Update architecture section:

```markdown
### Package Boundaries

swift-records is the **database operations layer** only. It should NOT contain:
- ❌ Query building extensions (aggregate functions, scalar functions, etc.)
- ❌ SQL expression builders
- ❌ Statement construction helpers

These belong in swift-structured-queries-postgres.

swift-records SHOULD contain:
- ✅ Database connection management (Database.Pool, Database.Writer, Database.Reader)
- ✅ Query execution methods (`.execute()`, `.fetchAll()`, `.fetchOne()`)
- ✅ Transaction support
- ✅ Migration system
- ✅ Test utilities (TestDatabasePool, schema isolation)
- ✅ Database-specific constants (Collation values, etc.)
```

## Summary of Changes

### Files Created (3):
1. `swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/PostgreSQL/PostgreSQLAggregates.swift` (new)

### Files Modified (2):
1. `swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/PostgreSQL/PostgreSQLFunctions.swift` (add ilike)
2. `swift-structured-queries-postgres/Sources/StructuredQueriesPostgresCore/Table.swift` (add count())

### Files Deleted from swift-records (6):
1. `Sources/Records/Extensions/QueryExpression.swift`
2. `Sources/Records/Extensions/PrimaryKeyedTableDefinition.swift`
3. `Sources/Records/Extensions/Select.swift`
4. `Sources/Records/Extensions/Table.swift`
5. `Sources/Records/Extensions/TableColumn.swift`
6. `Sources/Records/Extensions/Where.swift`

### Files Kept in swift-records (1):
1. `Sources/Records/Extensions/Collation.swift` (legitimate)

## Expected Outcome

- ✅ Clean separation of concerns between packages
- ✅ No duplicate code
- ✅ No ambiguity errors
- ✅ All PostgreSQL-specific query features in swift-structured-queries-postgres
- ✅ swift-records focuses purely on database operations
- ✅ ~500 lines of duplicate code removed
- ✅ Package boundaries clearly defined and enforced

## Benefits

1. **Maintainability**: Single source of truth for query language features
2. **Correctness**: Eliminates ambiguous function calls
3. **Clarity**: Clear package boundaries
4. **Upstream Alignment**: swift-structured-queries-postgres stays close to upstream
5. **Testability**: Query language and database operations tested separately
