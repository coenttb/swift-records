import Dependencies
import Records
import RecordsTestSupport
import Testing

/// Comprehensive snapshot tests for query building patterns.
///
/// This test suite mirrors upstream swift-structured-queries snapshot coverage,
/// adapted for PostgreSQL and async/await execution.
@Suite(
  "Query Snapshot Tests",
  .snapshots(record: .never),
  .dependencies {
    $0.envVars = .development
    $0.defaultDatabase = Database.TestDatabase.withReminderData()
  }
)
struct QuerySnapshotTests {

  // MARK: - Basic SELECT Patterns

  @Suite("SELECT Patterns")
  struct SelectPatterns {

    @Test("SELECT all columns")
    func selectAll() async {
      await assertQuery(
        Reminder.all.limit(3)
      ) {
        """
        SELECT "reminders"."id", "reminders"."assignedUserID", "reminders"."dueDate", "reminders"."isCompleted", "reminders"."isFlagged", "reminders"."notes", "reminders"."priority", "reminders"."remindersListID", "reminders"."title", "reminders"."updatedAt"
        FROM "reminders"
        LIMIT 3
        """
      } results: {
        """
        ┌──┐
        └──┘
        """
      }
    }

    @Test("SELECT specific columns")
    func selectColumns() async {
      await assertQuery(
        Reminder.select { $0.title }.order(by: \.title).limit(3)
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        ORDER BY "reminders"."title"
        LIMIT 3
        """
      } results: {
        """
        ┌─────────────────┐
        │ "Finish report" │
        │ "Groceries"     │
        │ "Haircut"       │
        └─────────────────┘
        """
      }
    }

    @Test("SELECT multiple columns")
    func selectMultipleColumns() async {
      await assertQuery(
        Reminder.select { ($0.id, $0.title) }.order(by: \.id).limit(3)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        ORDER BY "reminders"."id"
        LIMIT 3
        """
      } results: {
        """
        ┌───┬───────────────────┐
        │ 1 │ "Groceries"       │
        │ 2 │ "Haircut"         │
        │ 3 │ "Vet appointment" │
        └───┴───────────────────┘
        """
      }
    }

    @Test("SELECT with WHERE clause")
    func selectWithWhere() async {
      await assertQuery(
        Reminder
          .where { $0.isCompleted == true }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."isCompleted" = true)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬─────────────────┐
        │ 4 │ "Finish report" │
        └───┴─────────────────┘
        """
      }
    }

    @Test("SELECT with multiple WHERE conditions")
    func selectWithMultipleWhere() async {
      await assertQuery(
        Reminder
          .where { $0.isCompleted == false }
          .where { $0.isFlagged == true }
          .select { $0.title }
          .order(by: \.title)
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."isCompleted" = false) AND ("reminders"."isFlagged" = true)
        ORDER BY "reminders"."title"
        """
      } results: {
        """
        ┌────────────────┐
        │ "Haircut"      │
        │ "Team meeting" │
        └────────────────┘
        """
      }
    }

    @Test("SELECT with LIMIT and OFFSET")
    func selectWithLimitOffset() async {
      await assertQuery(
        Reminder.select { $0.title }.order(by: \.id).limit(2, offset: 2)
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        ORDER BY "reminders"."id"
        LIMIT 2 OFFSET 2
        """
      } results: {
        """
        ┌───────────────────┐
        │ "Vet appointment" │
        │ "Finish report"   │
        └───────────────────┘
        """
      }
    }

    @Test("SELECT DISTINCT")
    func selectDistinct() async {
      await assertQuery(
        Reminder.select { $0.remindersListID }.distinct().order(by: \.remindersListID)
      ) {
        """
        SELECT DISTINCT "reminders"."remindersListID"
        FROM "reminders"
        ORDER BY "reminders"."remindersListID"
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        │ 2 │
        └───┘
        """
      }
    }

    @Test("SELECT with NULL check")
    func selectWithNullCheck() async {
      await assertQuery(
        Reminder
          .where { $0.assignedUserID == nil }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."assignedUserID" IS NULL)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬───────────────────┐
        │ 2 │ "Haircut"         │
        │ 3 │ "Vet appointment" │
        │ 5 │ "Team meeting"    │
        └───┴───────────────────┘
        """
      }
    }

    @Test("SELECT with NOT NULL check")
    func selectWithNotNullCheck() async {
      await assertQuery(
        Reminder
          .where { $0.assignedUserID != nil }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."assignedUserID" IS NOT NULL)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬─────────────────┐
        │ 1 │ "Groceries"     │
        │ 4 │ "Finish report" │
        │ 6 │ "Review PR"     │
        └───┴─────────────────┘
        """
      }
    }

    @Test("SELECT with IN clause")
    func selectWithIn() async {
      await assertQuery(
        Reminder
          .where { [1, 2, 3].contains($0.id) }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."id" IN (1, 2, 3))
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬───────────────────┐
        │ 1 │ "Groceries"       │
        │ 2 │ "Haircut"         │
        │ 3 │ "Vet appointment" │
        └───┴───────────────────┘
        """
      }
    }
  }

  // MARK: - Comparison Operators

  @Suite("Comparison Operators")
  struct ComparisonOperators {

    @Test("Greater than")
    func greaterThan() async {
      await assertQuery(
        Reminder
          .where { $0.id > 4 }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."id" > 4)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬────────────────┐
        │ 5 │ "Team meeting" │
        │ 6 │ "Review PR"    │
        └───┴────────────────┘
        """
      }
    }

    @Test("Greater than or equal")
    func greaterThanOrEqual() async {
      await assertQuery(
        Reminder
          .where { $0.id >= 5 }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."id" >= 5)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬────────────────┐
        │ 5 │ "Team meeting" │
        │ 6 │ "Review PR"    │
        └───┴────────────────┘
        """
      }
    }

    @Test("Less than")
    func lessThan() async {
      await assertQuery(
        Reminder
          .where { $0.id < 3 }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."id" < 3)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬─────────────┐
        │ 1 │ "Groceries" │
        │ 2 │ "Haircut"   │
        └───┴─────────────┘
        """
      }
    }

    @Test("Not equal")
    func notEqual() async {
      await assertQuery(
        Reminder
          .where { $0.remindersListID != 1 }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."remindersListID" <> 1)
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬─────────────────┐
        │ 4 │ "Finish report" │
        │ 5 │ "Team meeting"  │
        │ 6 │ "Review PR"     │
        └───┴─────────────────┘
        """
      }
    }
  }

  // MARK: - Logical Operators

  @Suite("Logical Operators")
  struct LogicalOperators {

    @Test("AND operator")
    func andOperator() async {
      await assertQuery(
        Reminder
          .where { $0.isCompleted == false && $0.isFlagged == true }
          .select { $0.title }
          .order(by: \.title)
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE (("reminders"."isCompleted" = false) AND ("reminders"."isFlagged" = true))
        ORDER BY "reminders"."title"
        """
      } results: {
        """
        ┌────────────────┐
        │ "Haircut"      │
        │ "Team meeting" │
        └────────────────┘
        """
      }
    }

    @Test("OR operator")
    func orOperator() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 || $0.id == 6 }
          .select { ($0.id, $0.title) }
          .order(by: \.id)
      ) {
        """
        SELECT "reminders"."id", "reminders"."title"
        FROM "reminders"
        WHERE (("reminders"."id" = 1) OR ("reminders"."id" = 6))
        ORDER BY "reminders"."id"
        """
      } results: {
        """
        ┌───┬─────────────┐
        │ 1 │ "Groceries" │
        │ 6 │ "Review PR" │
        └───┴─────────────┘
        """
      }
    }

    @Test("NOT operator")
    func notOperator() async {
      await assertQuery(
        Reminder
          .where { !$0.isCompleted }
          .select { $0.title }
          .order(by: \.id)
          .limit(3)
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE NOT ("reminders"."isCompleted")
        ORDER BY "reminders"."id"
        LIMIT 3
        """
      } results: {
        """
        ┌───────────────────┐
        │ "Groceries"       │
        │ "Haircut"         │
        │ "Vet appointment" │
        └───────────────────┘
        """
      }
    }
  }

  // MARK: - String Operations

  @Suite("String Operations")
  struct StringOperations {

    @Test("String prefix")
    func stringPrefix() async {
      await assertQuery(
        Reminder
          .where { $0.title.hasPrefix("G") }
          .select { $0.title }
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."title" LIKE 'G%')
        """
      } results: {
        """
        ┌─────────────┐
        │ "Groceries" │
        └─────────────┘
        """
      }
    }

    @Test("String suffix")
    func stringSuffix() async {
      await assertQuery(
        Reminder
          .where { $0.title.hasSuffix("cut") }
          .select { $0.title }
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."title" LIKE '%cut')
        """
      } results: {
        """
        ┌───────────┐
        │ "Haircut" │
        └───────────┘
        """
      }
    }

    @Test("String contains")
    func stringContains() async {
      await assertQuery(
        Reminder
          .where { $0.title.contains("report") }
          .select { $0.title }
      ) {
        """
        SELECT "reminders"."title"
        FROM "reminders"
        WHERE ("reminders"."title" LIKE '%report%')
        """
      } results: {
        """
        ┌─────────────────┐
        │ "Finish report" │
        └─────────────────┘
        """
      }
    }
  }

  // MARK: - Aggregate Functions

  @Suite("Aggregate Functions")
  struct AggregateFunctions {

    @Test("COUNT all")
    func countAll() async {
      await assertQuery(
        Reminder.select { $0.count() }
      ) {
        """
        SELECT count("reminders"."id")
        FROM "reminders"
        """
      } results: {
        """
        ┌───┐
        │ 6 │
        └───┘
        """
      }
    }

    @Test("COUNT with WHERE")
    func countWithWhere() async {
      await assertQuery(
        Reminder
          .where { $0.isCompleted == true }
          .select { $0.count() }
      ) {
        """
        SELECT count("reminders"."id")
        FROM "reminders"
        WHERE ("reminders"."isCompleted" = true)
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        └───┘
        """
      }
    }

    @Test("COUNT DISTINCT")
    func countDistinct() async {
      await assertQuery(
        Reminder.select { $0.remindersListID.count(distinct: true) }
      ) {
        """
        SELECT count(DISTINCT "reminders"."remindersListID")
        FROM "reminders"
        """
      } results: {
        """
        ┌───┐
        │ 2 │
        └───┘
        """
      }
    }
  }

  // MARK: - INSERT Patterns (SQL Generation Only)

  @Suite("INSERT Patterns")
  struct InsertPatterns {

    @Test("INSERT single Draft record")
    func insertSingleDraft() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(
            remindersListID: 1,
            title: "Snapshot test task"
          )
        },
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Snapshot test task', '2040-02-14 23:31:30.000')
        """
      }
    }

    @Test("INSERT multiple Draft records")
    func insertMultipleDrafts() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(remindersListID: 1, title: "Task 1")
          Reminder.Draft(remindersListID: 1, title: "Task 2")
          Reminder.Draft(remindersListID: 2, title: "Task 3")
        },
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Task 1', '2040-02-14 23:31:30.000'), (NULL, NULL, false, false, '', NULL, 1, 'Task 2', '2040-02-14 23:31:30.000'), (NULL, NULL, false, false, '', NULL, 2, 'Task 3', '2040-02-14 23:31:30.000')
        """
      }
    }

    @Test("INSERT with RETURNING")
    func insertWithReturning() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(
            isCompleted: false,
            isFlagged: true,
            notes: "Test notes",
            priority: .high,
            remindersListID: 1,
            title: "Important task"
          )
        }
        .returning(\.self),
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, true, 'Test notes', 3, 1, 'Important task', '2040-02-14 23:31:30.000')
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      }
    }

    @Test("INSERT with NULL optional fields")
    func insertWithNullFields() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(
            assignedUserID: nil,
            priority: nil,
            remindersListID: 1,
            title: "Unassigned task"
          )
        },
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Unassigned task', '2040-02-14 23:31:30.000')
        """
      }
    }

    @Test("INSERT with enum value")
    func insertWithEnum() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(
            priority: .low,
            remindersListID: 1,
            title: "Low priority task"
          )
        },
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', 1, 1, 'Low priority task', '2040-02-14 23:31:30.000')
        """
      }
    }

    @Test("INSERT with boolean fields")
    func insertWithBooleans() {
      assertInlineSnapshot(
        of: Reminder.insert {
          Reminder.Draft(
            isCompleted: true,
            isFlagged: false,
            remindersListID: 1,
            title: "Completed task"
          )
        },
        as: .sql
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, true, false, '', NULL, 1, 'Completed task', '2040-02-14 23:31:30.000')
        """
      }
    }
  }

  // MARK: - UPDATE Patterns (SQL Generation Only)

  @Suite("UPDATE Patterns")
  struct UpdatePatterns {

    @Test("UPDATE single column with WHERE")
    func updateSingleColumn() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .update { $0.isCompleted = true },
        as: .sql
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true
        WHERE ("reminders"."id" = 1)
        """
      }
    }

    @Test("UPDATE multiple columns")
    func updateMultipleColumns() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .update { reminder in
            reminder.isCompleted = true
            reminder.notes = "Updated notes"
          },
        as: .sql
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true, "notes" = 'Updated notes'
        WHERE ("reminders"."id" = 1)
        """
      }
    }

    @Test("UPDATE with RETURNING")
    func updateWithReturning() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .update { $0.isCompleted = true }
          .returning(\.self),
        as: .sql
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true
        WHERE ("reminders"."id" = 1)
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      }
    }

    @Test("UPDATE with NULL value")
    func updateWithNull() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .update { $0.assignedUserID = nil },
        as: .sql
      ) {
        """
        UPDATE "reminders"
        SET "assignedUserID" = NULL
        WHERE ("reminders"."id" = 1)
        """
      }
    }

    @Test("UPDATE with complex WHERE")
    func updateComplexWhere() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 && $0.isCompleted == false }
          .update { $0.isFlagged = true },
        as: .sql
      ) {
        """
        UPDATE "reminders"
        SET "isFlagged" = true
        WHERE (("reminders"."id" = 1) AND ("reminders"."isCompleted" = false))
        """
      }
    }
  }

  // MARK: - DELETE Patterns (SQL Generation Only)

  @Suite("DELETE Patterns")
  struct DeletePatterns {

    @Test("DELETE with WHERE clause")
    func deleteWithWhere() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .delete(),
        as: .sql
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" = 1)
        """
      }
    }

    @Test("DELETE with RETURNING")
    func deleteWithReturning() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 }
          .delete()
          .returning(\.self),
        as: .sql
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" = 1)
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      }
    }

    @Test("DELETE with complex WHERE")
    func deleteComplexWhere() {
      assertInlineSnapshot(
        of: Reminder
          .where { $0.id == 1 && $0.isCompleted && $0.priority == Priority.high }
          .delete(),
        as: .sql
      ) {
        """
        DELETE FROM "reminders"
        WHERE ((("reminders"."id" = 1) AND "reminders"."isCompleted") AND ("reminders"."priority" = 3))
        """
      }
    }

    @Test("DELETE using find()")
    func deleteWithFind() {
      assertInlineSnapshot(
        of: Reminder.find(1).delete(),
        as: .sql
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" IN (1))
        """
      }
    }

    @Test("DELETE using find() with sequence")
    func deleteWithFindSequence() {
      assertInlineSnapshot(
        of: Reminder.find([1, 2, 3]).delete(),
        as: .sql
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" IN (1, 2, 3))
        """
      }
    }
  }
}
