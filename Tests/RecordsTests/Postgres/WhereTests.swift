// import Foundation
// import InlineSnapshotTesting
// import StructuredQueriesPostgres
// import RecordsTestSupport
// import Testing
//
// extension SnapshotTests {
//  @Suite struct WhereTests {
//    @Test func and() {
//      assertInlineSnapshot(
//        of: Reminder.where(\.isCompleted).and(Reminder.where(\.isFlagged))
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE ("reminders"."isCompleted") AND ("reminders"."isFlagged")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: (Reminder.where(\.isCompleted) && Reminder.where(\.isFlagged))
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE ("reminders"."isCompleted") AND ("reminders"."isFlagged")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: Reminder.all.and(Reminder.where(\.isFlagged)).count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE "reminders"."isFlagged"
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: Reminder.where(\.isFlagged).and(Reminder.all).count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE "reminders"."isFlagged"
//        """
//      }
//    }
//
//    @Test func or() {
//      assertInlineSnapshot(
//        of: Reminder.where(\.isCompleted).or(Reminder.where(\.isFlagged))
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE ("reminders"."isCompleted") OR ("reminders"."isFlagged")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: (Reminder.where(\.isCompleted) || Reminder.where(\.isFlagged))
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE ("reminders"."isCompleted") OR ("reminders"."isFlagged")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: Reminder.all.or(Reminder.where(\.isFlagged)).count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE "reminders"."isFlagged"
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: Reminder.where(\.isFlagged).or(Reminder.all).count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE "reminders"."isFlagged"
//        """
//      }
//    }
//
//    @Test func not() {
//      assertInlineSnapshot(
//        of: Reminder.where(\.isCompleted).not()
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE NOT ("reminders"."isCompleted")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: (!Reminder.where(\.isCompleted))
//          .count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE NOT ("reminders"."isCompleted")
//        """
//      }
//      
//      assertInlineSnapshot(
//        of: Reminder.all.not().count(),
//        as: .sql
//      ) {
//        """
//        SELECT count(*)
//        FROM "reminders"
//        WHERE NOT (1)
//        """
//      }
//    }
//
//    @Test func buildArray() {
//      let terms = ["daily", "monthly"]
//      assertInlineSnapshot(
//        of: RemindersList.where {
//          for term in terms {
//            $0.title.contains(term)
//          }
//        },
//        as: .sql
//      ) {
//        """
//        SELECT "remindersLists"."id", "remindersLists"."color", "remindersLists"."title", "remindersLists"."position"
//        FROM "remindersLists"
//        WHERE ("remindersLists"."title" LIKE '%daily%') AND ("remindersLists"."title" LIKE '%monthly%')
//        """
//      }
//    }
//  }
// }
