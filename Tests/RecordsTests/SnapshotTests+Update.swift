import Dependencies
import Records
import RecordsTestSupport
import Testing

// MARK: - UPDATE Patterns

extension SnapshotTests {
  @Suite("UPDATE Patterns")
  struct UpdatePatterns {

    @Test("UPDATE single column with WHERE")
    func updateSingleColumn() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .update { $0.isCompleted = true }
          .returning(\.id)
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true
        WHERE ("reminders"."id" = 1)
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        └───┘
        """
      }
    }

    @Test("UPDATE multiple columns")
    func updateMultipleColumns() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .update { reminder in
            reminder.isCompleted = true
            reminder.notes = "Updated notes"
          }
          .returning(\.id)
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true, "notes" = 'Updated notes'
        WHERE ("reminders"."id" = 1)
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        └───┘
        """
      }
    }

    @Test("UPDATE with RETURNING full record")
    func updateWithReturning() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .update { $0.isCompleted = true }
          .returning(\.self)
      ) {
        """
        UPDATE "reminders"
        SET "isCompleted" = true
        WHERE ("reminders"."id" = 1)
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      } results: {
        """
        ┌─────────────────────────────────────────────┐
        │ Reminder(                                   │
        │   id: 1,                                    │
        │   assignedUserID: 1,                        │
        │   dueDate: Date(2001-01-01T00:00:00.000Z),  │
        │   isCompleted: true,                        │
        │   isFlagged: false,                         │
        │   notes: "Milk, Eggs, Apples",              │
        │   priority: nil,                            │
        │   remindersListID: 1,                       │
        │   title: "Groceries",                       │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z) │
        │ )                                           │
        └─────────────────────────────────────────────┘
        """
      }
    }

    @Test("UPDATE with NULL value")
    func updateWithNull() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .update { $0.assignedUserID = nil }
          .returning(\.assignedUserID)
      ) {
        """
        UPDATE "reminders"
        SET "assignedUserID" = NULL
        WHERE ("reminders"."id" = 1)
        RETURNING "assignedUserID"
        """
      } results: {
        """
        ┌─────┐
        │ nil │
        └─────┘
        """
      }
    }

    @Test("UPDATE with complex WHERE")
    func updateComplexWhere() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 && $0.isCompleted == false }
          .update { $0.isFlagged = true }
          .returning(\.id)
      ) {
        """
        UPDATE "reminders"
        SET "isFlagged" = true
        WHERE (("reminders"."id" = 1) AND ("reminders"."isCompleted" = false))
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        └───┘
        """
      }
    }
  }
}
