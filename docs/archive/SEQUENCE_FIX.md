# PostgreSQL Sequence Reset Fix

## Problem

When running INSERT execution tests, all 10 tests were failing with `PSQLError`.

## Root Cause

The test database setup in `insertReminderSampleData()` was inserting records with explicit IDs:

```sql
INSERT INTO "reminders" ("id", ...) VALUES
(1, ...), (2, ...), (3, ...), (4, ...), (5, ...), (6, ...)
```

**PostgreSQL behavior**: When you INSERT with explicit IDs, the SERIAL sequence is **NOT** automatically updated.

Result:
- Database has reminders with IDs 1-6
- Sequence `reminders_id_seq` is still at 1
- Next auto-generated ID tries to use 1 → **PRIMARY KEY CONFLICT**

This is a classic PostgreSQL gotcha that doesn't occur in SQLite.

## Solution

Added sequence resets after all explicit inserts in `TestDatabaseHelper.swift`:

```swift
// Reset sequences to correct values after explicit inserts
// Note: Use pg_get_serial_sequence() to handle quoted table names correctly
try await db.execute("""
    SELECT setval(pg_get_serial_sequence('"remindersLists"', 'id'), (SELECT MAX(id) FROM "remindersLists"))
""")

try await db.execute("""
    SELECT setval(pg_get_serial_sequence('"reminders"', 'id'), (SELECT MAX(id) FROM "reminders"))
""")

try await db.execute("""
    SELECT setval(pg_get_serial_sequence('"users"', 'id'), (SELECT MAX(id) FROM "users"))
""")

try await db.execute("""
    SELECT setval(pg_get_serial_sequence('"tags"', 'id'), (SELECT MAX(id) FROM "tags"))
""")
```

### Why `pg_get_serial_sequence()`?

PostgreSQL sequence naming with quoted identifiers:
- Unquoted table `users` → sequence `users_id_seq`
- Quoted table `"reminders"` → sequence `"reminders_id_seq"` (with quotes!)

Using `pg_get_serial_sequence('"tableName"', 'columnName')` automatically handles this complexity.

## Why This Works

`setval()` updates the sequence to the maximum existing ID, so the next auto-generated value will be `MAX(id) + 1`, avoiding conflicts.

## Prevention

**Rule for test data setup**: Always reset sequences after inserting with explicit IDs in PostgreSQL.

**Alternative**: Don't use explicit IDs in test data - let PostgreSQL auto-generate them. But this makes test data less predictable.

## Files Changed

- `/Users/coen/Developer/coenttb/swift-records/Sources/RecordsTestSupport/TestDatabaseHelper.swift:218-233`

## Test Impact

All 10 INSERT execution tests should now pass:
- ✅ INSERT basic Draft  
- ✅ INSERT with all fields specified
- ✅ INSERT multiple Drafts
- ✅ INSERT with NULL optional fields
- ✅ INSERT with priority levels
- ✅ INSERT and verify with SELECT
- ✅ INSERT with boolean flags
- ✅ INSERT into different lists
- ✅ INSERT with date fields
- ✅ INSERT without RETURNING
