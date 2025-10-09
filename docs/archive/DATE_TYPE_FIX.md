# PostgreSQL DATE Type Fix

## Problem

The "INSERT with date fields" test was failing with:

```
Expectation failed: (abs(dueDate.timeIntervalSince(futureDate)) → 71873.92) < 1.0
```

The time difference was ~20 hours, not a rounding error.

## Root Cause

PostgreSQL's `DATE` type vs `TIMESTAMP`:

**Schema definition**:
```sql
"dueDate" DATE
```

**DATE behavior**:
- Stores only: `YYYY-MM-DD` (date part)
- Loses: time-of-day component

**Example**:
```
Input:  2025-10-09 15:30:45 (3:30 PM)
Stored: 2025-10-09 00:00:00 (midnight)
```

## Solution

Compare only date components, not time:

```swift
// OLD (fails for DATE columns):
#expect(abs(dueDate.timeIntervalSince(futureDate)) < 1.0)

// NEW (compares date components only):
let calendar = Calendar.current
let insertedComponents = calendar.dateComponents([.year, .month, .day], from: futureDate)
let retrievedComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
#expect(insertedComponents == retrievedComponents)
```

## Why This Matters

**PostgreSQL date types**:
- `DATE`: Date only (YYYY-MM-DD)
- `TIMESTAMP`: Date + time (YYYY-MM-DD HH:MM:SS)
- `TIMESTAMPTZ`: Date + time + timezone

The Reminder schema uses `DATE` because it only needs day-level precision for due dates.

## Alternative Solutions

1. **Change schema to TIMESTAMP** (if time precision needed):
   ```sql
   "dueDate" TIMESTAMP
   ```

2. **Normalize to midnight before comparison**:
   ```swift
   let calendar = Calendar.current
   let normalizedInput = calendar.startOfDay(for: futureDate)
   let normalizedOutput = calendar.startOfDay(for: dueDate)
   #expect(normalizedInput == normalizedOutput)
   ```

3. **Use DateComponents from start**:
   ```swift
   let futureDate = Calendar.current.date(
       from: DateComponents(year: 2025, month: 10, day: 9)
   )!
   ```

## Files Changed

- `/Users/coen/Developer/coenttb/swift-records/Tests/RecordsTests/InsertExecutionTests.swift:214-240`

## Test Impact

- ✅ All 94 tests now passing (including "INSERT with date fields")
