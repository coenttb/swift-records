# swift-records Test Improvements Analysis

## Current State Assessment

After refactoring to integration-only testing, we can now improve test quality by using `assertQuery` more consistently.

### What `assertQuery` Provides

```swift
await assertQuery(statement) {
    """
    SQL string  // ❌ Remove - sq-postgres validates this
    """
} results: {
    """
    ┌─────┬─────┐
    │ ... │ ... │  // ✅ Keep - validates actual data returned
    └─────┴─────┘
    """
}
```

**Key insight:** For swift-records, we should **ONLY use the `results:` closure**, not the SQL validation.

---

## Test Categories

### ✅ Already Good (Keep As-Is)

**JSONBIntegrationTests** - Lines 512-606
- Uses `assertQuery` with both SQL and results
- **Note:** Can remove `sql:` closures (redundant with sq-postgres)
- Example:
  ```swift
  @Test("Contains operator query snapshot")
  func containsQuerySnapshot() async {
      await assertQuery(
          UserProfile.where { $0.settings.contains(["theme": "dark"]) }
      ) {
          "SELECT..." // ❌ Remove this
      } results: {
          """
          ┌───────────┐
          │ "Bob"     │  // ✅ Keep this - validates actual data
          └───────────┘
          """
      }
  }
  ```

**TransactionTests, TriggerTests, ErrorHandlingTests**
- Test side effects, not SELECT results
- Current patterns are appropriate
- No changes needed

---

### 🔄 Needs Improvement

#### 1. SelectExecutionTests.swift

**Current Pattern (Manual Assertions):**
```swift
@Test("SELECT specific columns")
func selectColumns() async throws {
    let titles = try await db.read { db in
        try await Reminder.select { $0.title }.fetchAll(db)
    }
    #expect(titles.count == 6)
    #expect(titles.contains("Groceries"))
    #expect(titles.contains("Haircut"))
}
```

**Improved Pattern (Results Snapshot):**
```swift
@Test("SELECT specific columns returns correct data")
func selectColumns() async {
    await assertQuery(
        Reminder.select { $0.title }.order(by: \.title)
    ) results: {
        """
        ┌───────────────────┐
        │ "Finish report"   │
        │ "Groceries"       │
        │ "Haircut"         │
        │ "Review PR"       │
        │ "Team meeting"    │
        │ "Vet appointment" │
        └───────────────────┘
        """
    }
}
```

**Benefits:**
- Exact data validation (not just counts)
- Visual snapshot (easy to review)
- Catches regressions in data shape
- No manual count assertions

**Tests to Convert:**
- `selectAll()` → Use `assertQuery` with results snapshot
- `selectColumns()` → Use `assertQuery` with results snapshot
- `selectWithWhere()` → Use `assertQuery` with results snapshot
- `selectWithOrderBy()` → Use `assertQuery` with results snapshot
- `selectWithLimit()` → Use `assertQuery` with results snapshot
- `selectWithNullChecks()` → Use `assertQuery` with results snapshot
- `selectWithIn()` → Use `assertQuery` with results snapshot
- `selectWithLike()` → Use `assertQuery` with results snapshot
- `fetchOne()` → Use `assertQuery` with results snapshot

**Keep Manual Assertions For:**
- `selectWithLimitOffset()` - Tests pagination logic (compare offsets)
- `selectWithBooleanOperators()` - Tests logical operators (manual check needed)
- `fetchOneNoMatch()` - Tests nil case (no snapshot needed)

---

#### 2. InsertExecutionTests.swift

**Current Pattern:**
```swift
@Test("INSERT basic Draft")
func insertBasicDraft() async throws {
    let inserted = try await db.write { db in
        try await Reminder.insert { ... }.returning(\.self).fetchAll(db)
    }
    #expect(inserted.count == 1)
    #expect(inserted.first?.title == "New task")
    // ... manual cleanup
}
```

**Improved Pattern:**
```swift
@Test("INSERT basic Draft returns correct data")
func insertBasicDraft() async {
    await assertQuery(
        Reminder.insert {
            Reminder.Draft(remindersListID: 1, title: "New task")
        }.returning { ($0.title, $0.remindersListID, $0.isCompleted) }
    ) results: {
        """
        ┌────────────┬───┬───────┐
        │ "New task" │ 1 │ false │
        └────────────┴───┴───────┘
        """
    }
}
```

**Benefits:**
- Validates exact inserted data
- No cleanup needed (uses rollback)
- Verifies default values
- Catches encoding/decoding issues

**Tests to Convert:**
- `insertBasicDraft()` → Use `assertQuery` with results
- `insertMultipleDrafts()` → Use `assertQuery` with results
- `insertWithPriorities()` → Use `assertQuery` with results
- `insertWithBooleanFlags()` → Use `assertQuery` with results

**Keep Manual Tests For:**
- `insertWithAllFields()` - Complex field validation
- `insertAndVerify()` - Tests round-trip behavior
- `insertWithoutReturning()` - Tests execute() without RETURNING

---

#### 3. UpdateExecutionTests.swift & DeleteExecutionTests.swift

**Review Needed:**
- Check if any return data that should be snapshot
- Most UPDATE/DELETE tests verify side effects, not results
- Keep manual assertions for row count checks

---

#### 4. Remove SQL Snapshots from Feature Tests

**JSONBIntegrationTests** - Remove SQL validation, keep results:
```swift
// ❌ Remove this
{
    """
    SELECT "user_profiles"."name"
    FROM "user_profiles"
    WHERE ("user_profiles"."settings" ? 'notifications')
    ORDER BY "user_profiles"."name"
    """
}

// ✅ Keep this
results: {
    """
    ┌─────────┐
    │ "Bob"   │
    │ "Diana" │
    └─────────┘
    """
}
```

---

## Recommended Refactoring Priority

### Phase 1: Remove SQL Snapshots (Quick Win)
- **JSONBIntegrationTests** - Remove all `sql:` closures
- **FullTextSearchIntegrationTests** - Remove all `sql:` closures
- **Effort:** Low, **Impact:** High (removes redundancy)

### Phase 2: Add Results Snapshots to SELECT Tests
- **SelectExecutionTests** - Convert 9 tests to use `assertQuery` with results
- **Effort:** Medium, **Impact:** High (better validation)

### Phase 3: Add Results Snapshots to INSERT Tests
- **InsertExecutionTests** - Convert 4-5 tests to use `assertQuery` with results
- **Effort:** Medium, **Impact:** Medium (better validation + no cleanup)

### Phase 4: Review UPDATE/DELETE Tests
- Check if any benefit from results snapshots
- **Effort:** Low, **Impact:** Low

---

## Pattern Guidelines

### When to Use `assertQuery`

✅ **Use `assertQuery` (results only) when:**
- Testing SELECT queries that return data
- Testing INSERT...RETURNING queries
- Testing UPDATE...RETURNING queries
- Want to validate exact data shape/content
- Want visual regression testing

❌ **Don't use `assertQuery` when:**
- Testing side effects (transactions, triggers)
- Testing error conditions
- Testing nil/empty results (manual assertions clearer)
- Testing pagination logic (need to compare result sets)
- Testing `.execute()` without RETURNING

### Template for Conversion

```swift
// Before
@Test("Test name")
func testName() async throws {
    let results = try await db.read { db in
        try await Table.where { ... }.fetchAll(db)
    }
    #expect(results.count == N)
    #expect(results.first?.field == value)
}

// After
@Test("Test name returns correct data")
func testName() async {
    await assertQuery(
        Table.where { ... }.select { ... }.order(by: ...)  // Add order for determinism
    ) results: {
        """
        ┌────────┬────────┐
        │ value1 │ value2 │
        └────────┴────────┘
        """
    }
}
```

---

## Expected Outcomes

**After Phase 1:**
- ~400 lines removed (SQL snapshots)
- 100% focus on integration testing

**After Phase 2 & 3:**
- ~15-20 tests converted to `assertQuery`
- Better data validation
- Easier to spot regressions
- Less manual cleanup code

**Test Coverage:**
- Same functional coverage
- Better data validation
- Visual regression testing
- Clearer test intent

---

## Next Steps

1. **Phase 1:** Remove SQL snapshots from JSONBIntegrationTests (5 tests)
2. **Phase 2:** Convert SelectExecutionTests to use assertQuery (9 tests)
3. **Phase 3:** Convert InsertExecutionTests to use assertQuery (4-5 tests)
4. **Phase 4:** Review and document patterns in TESTING.md
