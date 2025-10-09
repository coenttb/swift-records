import Dependencies
import Records
import RecordsTestSupport
import Testing

// MARK: - INSERT Patterns

extension SnapshotTests {
  @Suite("INSERT Patterns")
  struct InsertPatterns {

    @Test("INSERT single Draft record")
    func insertSingleDraft() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(
            remindersListID: 1,
            title: "Snapshot test task"
          )
        }
        .returning(\.id)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Snapshot test task', '2040-02-14 23:31:30.000')
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 7 │
        └───┘
        """
      }
    }

    @Test("INSERT multiple Draft records")
    func insertMultipleDrafts() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(remindersListID: 1, title: "Task 1")
          Reminder.Draft(remindersListID: 1, title: "Task 2")
          Reminder.Draft(remindersListID: 2, title: "Task 3")
        }
        .returning(\.id)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Task 1', '2040-02-14 23:31:30.000'), (NULL, NULL, false, false, '', NULL, 1, 'Task 2', '2040-02-14 23:31:30.000'), (NULL, NULL, false, false, '', NULL, 2, 'Task 3', '2040-02-14 23:31:30.000')
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 7 │
        │ 8 │
        │ 9 │
        └───┘
        """
      }
    }

    @Test("INSERT with RETURNING full record")
    func insertWithReturning() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(
            isCompleted: false,
            isFlagged: true,
            notes: "Test notes",
            priority: .high,
            remindersListID: 1,
            title: "Important task"
          )
        }
        .returning(\.self)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, true, 'Test notes', 3, 1, 'Important task', '2040-02-14 23:31:30.000')
        RETURNING "id", "assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt"
        """
      } results: {
        """
        ┌──────────────────────────────────────────────┐
        │ Reminder(                                    │
        │   id: 7,                                     │
        │   assignedUserID: nil,                       │
        │   dueDate: nil,                              │
        │   isCompleted: false,                        │
        │   isFlagged: true,                           │
        │   notes: "Test notes",                       │
        │   priority: Priority.high,                   │
        │   remindersListID: 1,                        │
        │   title: "Important task",                   │
        │   updatedAt: Date(2040-02-14T23:31:30.000Z)  │
        │ )                                            │
        └──────────────────────────────────────────────┘
        """
      }
    }

    @Test("INSERT with NULL optional fields")
    func insertWithNullFields() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(
            assignedUserID: nil,
            priority: nil,
            remindersListID: 1,
            title: "Unassigned task"
          )
        }
        .returning(\.id)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', NULL, 1, 'Unassigned task', '2040-02-14 23:31:30.000')
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 7 │
        └───┘
        """
      }
    }

    @Test("INSERT with enum value")
    func insertWithEnum() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(
            priority: .low,
            remindersListID: 1,
            title: "Low priority task"
          )
        }
        .returning(\.id)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, false, false, '', 1, 1, 'Low priority task', '2040-02-14 23:31:30.000')
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 7 │
        └───┘
        """
      }
    }

    @Test("INSERT with boolean fields")
    func insertWithBooleans() async {
      await assertQuery(
        Reminder.insert {
          Reminder.Draft(
            isCompleted: true,
            isFlagged: false,
            remindersListID: 1,
            title: "Completed task"
          )
        }
        .returning(\.id)
      ) {
        """
        INSERT INTO "reminders"
        ("assignedUserID", "dueDate", "isCompleted", "isFlagged", "notes", "priority", "remindersListID", "title", "updatedAt")
        VALUES
        (NULL, NULL, true, false, '', NULL, 1, 'Completed task', '2040-02-14 23:31:30.000')
        RETURNING "id"
        """
      } results: {
        """
        ┌───┐
        │ 7 │
        └───┘
        """
      }
    }
  }
}
