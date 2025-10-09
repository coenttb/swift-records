import Dependencies
import Records
import RecordsTestSupport
import Testing

// MARK: - DELETE Patterns

extension SnapshotTests {
  @Suite("DELETE Patterns")
  struct DeletePatterns {

    @Test("DELETE with WHERE clause")
    func deleteWithWhere() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .delete()
          .returning(\.id)
      ) {
        """
        DELETE FROM "reminders"
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

    @Test("DELETE with RETURNING full record")
    func deleteWithReturning() async {
      await assertQuery(
        Reminder
          .where { $0.id == 1 }
          .delete()
          .returning(\.self)
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" = 1)
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      } results: {
        """
        ┌──────────────────────────────────────────────┐
        │ Reminder(                                    │
        │   id: 1,                                     │
        │   assignedUserID: 1,                         │
        │   dueDate: Date(2001-01-01T00:00:00.000Z),   │
        │   isCompleted: false,                        │
        │   isFlagged: false,                          │
        │   notes: "Buy milk and eggs",                │
        │   priority: nil,                             │
        │   remindersListID: 1,                        │
        │   title: "Groceries",                        │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z)  │
        │ )                                            │
        └──────────────────────────────────────────────┘
        """
      }
    }

    @Test("DELETE with complex WHERE")
    func deleteComplexWhere() async {
      await assertQuery(
        Reminder
          .where { $0.id == 4 && $0.isCompleted && $0.priority == Priority.low }
          .delete()
          .returning(\.id)
      ) {
        """
        DELETE FROM "reminders"
        WHERE ((("reminders"."id" = 4) AND "reminders"."isCompleted") AND ("reminders"."priority" = 1))
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 4 │
        └───┘
        """
      }
    }

    @Test("DELETE using find()")
    func deleteWithFind() async {
      await assertQuery(
        Reminder.find(2).delete().returning(\.id)
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" IN (2))
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 2 │
        └───┘
        """
      }
    }

    @Test("DELETE using find() with sequence")
    func deleteWithFindSequence() async {
      await assertQuery(
        Reminder.find([5, 6]).delete().returning(\.id)
      ) {
        """
        DELETE FROM "reminders"
        WHERE ("reminders"."id" IN (5, 6))
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 5 │
        │ 6 │
        └───┘
        """
      }
    }
  }
}
