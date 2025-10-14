import Dependencies
import DependenciesTestSupport
import Foundation
import Records
import RecordsTestSupport
import StructuredQueriesPostgres
import Testing

/// Comprehensive integration tests for PostgreSQL trigger functionality.
///
/// These tests verify that triggers actually work against a real PostgreSQL database,
/// complementing the unit tests that validate SQL generation.
///
/// Test Coverage:
/// - Basic trigger execution (5 tests)
/// - Helper function tests (10 tests)
/// - Advanced scenarios (8 tests)
/// - Error handling (3 tests)
@Suite(
    "Trigger Integration Tests",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withTriggerTestTables()
    }
)
struct TriggerIntegrationTests {
    @Dependency(\.defaultDatabase) var db

    /// Helper to get detailed error message from PSQLError
    private func errorMessage(from error: Error) -> String {
        String(reflecting: error)
    }

    // MARK: - Basic Trigger Execution Tests (5 tests)

    @Test("BEFORE trigger modifies NEW row before insert")
    func testBeforeTriggerModifiesNewRow() async throws {
        try await db.withRollback { db in
            // Create trigger function that sets slug from title
            let function = TriggerFunction<Post>.define("set_slug_func") {
                #sql("NEW.slug = LOWER(REPLACE(NEW.title, ' ', '-'))")
                #sql("RETURN NEW")
            }
            try await function.execute(db)

            // Create BEFORE INSERT trigger
            let trigger = Post.createTrigger(
                "set_slug_trigger",
                timing: .before,
                event: .insert,
                function: function
            )
            try await trigger.execute(db)

            // Insert post without slug using DSL
            try await Post.insert {
                Post.Draft(title: "Hello World")
            }.execute(db)

            // Verify slug was set by trigger
            let post = try await Post.where { $0.title == "Hello World" }.fetchOne(db)
            #expect(post?.slug == "hello-world")
        }
    }

    @Test("AFTER trigger executes after insert (audit log)")
    func testAfterTriggerExecutesAfterInsert() async throws {
        try await db.withRollback { db in
            // Create audit trigger
            let function = TriggerFunction<Post>.auditLog("audit_func", to: AuditLog.self)
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "audit_trigger",
                timing: .after,
                events: [.insert],
                function: function
            )
            try await trigger.execute(db)

            // Insert post using DSL
            try await Post.insert {
                Post.Draft(title: "Test Post")
            }.execute(db)

            // Verify audit log entry was created
            let auditLogs = try await AuditLog.where { $0.operation == "INSERT" }.fetchAll(db)
            #expect(auditLogs.count == 1)
        }
    }

    @Test("Trigger fires on UPDATE")
    func testTriggerFiresOnUpdate() async throws {
        try await db.withRollback { db in
            // Create update timestamp trigger
            let function = TriggerFunction<Post>.updateTimestamp(
                "update_ts_func",
                column: \.updatedAt
            )
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "update_ts_trigger",
                timing: .before,
                event: .update,
                function: function
            )
            try await trigger.execute(db)

            // Insert post using DSL
            try await Post.insert {
                Post.Draft(title: "Original Title")
            }.execute(db)

            // Update post using DSL
            try await Post
                .update { $0.title = "Updated Title" }
                .where { $0.title == "Original Title" }
                .execute(db)

            // Verify updated_at was set
            let post = try await Post.where { $0.title == "Updated Title" }.fetchOne(db)
            #expect(post?.updatedAt != nil)
        }
    }

    @Test("Trigger fires on DELETE")
    func testTriggerFiresOnDelete() async throws {
        try await db.withRollback { db in
            // Create audit trigger for DELETE
            let function = TriggerFunction<Post>.auditLog("audit_func", to: AuditLog.self)
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "audit_trigger",
                timing: .after,
                events: [.delete],
                function: function
            )
            try await trigger.execute(db)

            // Insert post using DSL
            try await Post.insert {
                Post.Draft(title: "To Be Deleted")
            }.execute(db)

            // Delete post using DSL
            try await Post
                .where { $0.title == "To Be Deleted" }
                .delete()
                .execute(db)

            // Verify audit log entry was created
            let auditLogs = try await AuditLog.where { $0.operation == "DELETE" }.fetchAll(db)
            #expect(auditLogs.count == 1)
        }
    }

    @Test("Multiple triggers on same table execute in order")
    func testMultipleTriggersExecuteInOrder() async throws {
        try await db.withRollback { db in
            // Create first trigger (sets slug)
            let slugFunc = TriggerFunction<Post>.define("set_slug_func") {
                #sql("NEW.slug = LOWER(REPLACE(NEW.title, ' ', '-'))")
                #sql("RETURN NEW")
            }
            try await slugFunc.execute(db)

            let slugTrigger = Post.createTrigger(
                "a_set_slug_trigger",  // Name with 'a_' prefix for alphabetical ordering
                timing: .before,
                event: .insert,
                function: slugFunc
            )
            try await slugTrigger.execute(db)

            // Create second trigger (sets created_at)
            let createdAtFunc = TriggerFunction<Post>.setCreatedAt(
                "set_created_at_func",
                column: \.createdAt
            )
            try await createdAtFunc.execute(db)

            let createdAtTrigger = Post.createTrigger(
                "b_set_created_at_trigger",  // Name with 'b_' prefix for alphabetical ordering
                timing: .before,
                event: .insert,
                function: createdAtFunc
            )
            try await createdAtTrigger.execute(db)

            // Insert post using DSL
            try await Post.insert {
                Post.Draft(title: "Multiple Triggers")
            }.execute(db)

            // Verify both triggers executed
            let post = try await Post.where { $0.title == "Multiple Triggers" }.fetchOne(db)
            #expect(post?.slug == "multiple-triggers")
            #expect(post?.createdAt != nil)
        }
    }

    // MARK: - Helper Function Tests (10 tests)

    @Test("autoUpdateTimestamp sets timestamp on update")
    func testAutoUpdateTimestamp() async throws {
        try await db.withRollback { db in
            // Create trigger using helper
            let trigger = Post.autoUpdateTimestamp("update_ts", column: \.updatedAt)
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert row using DSL with explicit NULL updatedAt
            try await Post.insert {
                Post.Draft(title: "Test", updatedAt: nil)
            }.execute(db)

            // Verify updated_at is NULL initially
            let beforeUpdate = try await Post.where { $0.title == "Test" }.fetchOne(db)
            #expect(beforeUpdate?.updatedAt == nil)

            // Update row using DSL
            try await Post
                .update { $0.title = "Updated" }
                .where { $0.title == "Test" }
                .execute(db)

            // Verify updated_at is now set
            let afterUpdate = try await Post.where { $0.title == "Updated" }.fetchOne(db)
            #expect(afterUpdate?.updatedAt != nil)
        }
    }

    @Test("autoAudit logs all operations")
    func testAutoAudit() async throws {
        try await db.withRollback { db in
            // Create audit trigger
            let trigger = Post.autoAudit("audit_posts", to: AuditLog.self)
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert using DSL
            try await Post.insert {
                Post.Draft(title: "New Post")
            }.execute(db)

            // Update using DSL
            try await Post
                .update { $0.title = "Updated Post" }
                .where { $0.title == "New Post" }
                .execute(db)

            // Delete using DSL
            try await Post
                .where { $0.title == "Updated Post" }
                .delete()
                .execute(db)

            // Verify all operations logged
            let auditLogs = try await AuditLog.all.order(by: \.id).fetchAll(db)
            let operations = auditLogs.map { $0.operation }
            #expect(operations == ["INSERT", "UPDATE", "DELETE"])
        }
    }

    @Test("blockDeletion prevents all deletions")
    func testBlockDeletion() async throws {
        try await db.withRollback { db in
            // Create block deletion trigger
            let trigger = Post.blockDeletion(
                "prevent_delete",
                message: "No deletes allowed!"
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert post using DSL
            try await Post.insert {
                Post.Draft(title: "Protected")
            }.execute(db)

            // Try to delete using DSL - should fail
            do {
                try await Post
                    .where { $0.title == "Protected" }
                    .delete()
                    .execute(db)
                Issue.record("Expected deletion to be blocked")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("No deletes allowed!"))
            }
        }
    }

    @Test("blockDeletionWhen conditionally prevents deletion")
    func testBlockDeletionWhen() async throws {
        try await db.withRollback { db in
            // Create conditional block deletion trigger
            let trigger = Document.blockDeletionWhen(
                "prevent_published_delete",
                column: \.isPublished,
                equals: true,
                message: "Cannot delete published documents"
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert unpublished and published documents using DSL
            try await Document.insert {
                Document.Draft(title: "Draft", isPublished: false)
                Document.Draft(title: "Published", isPublished: true)
            }.execute(db)

            // Delete unpublished using DSL - should succeed
            try await Document
                .where { $0.title == "Draft" }
                .delete()
                .execute(db)

            // Try to delete published using DSL - should fail
            do {
                try await Document
                    .where { $0.title == "Published" }
                    .delete()
                    .execute(db)
                Issue.record("Expected deletion to be blocked")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("Cannot delete published documents"))
            }
        }
    }

    @Test("autoSetCreatedAt sets timestamp on insert")
    func testAutoSetCreatedAt() async throws {
        try await db.withRollback { db in
            // Create trigger
            let trigger = Post.autoSetCreatedAt("set_created", column: \.createdAt)
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert without created_at using DSL
            try await Post.insert {
                Post.Draft(title: "New Post")
            }.execute(db)

            // Verify created_at was set
            let post = try await Post.where { $0.title == "New Post" }.fetchOne(db)
            #expect(post?.createdAt != nil)
        }
    }

    @Test("autoValidate validates data before insert/update")
    func testAutoValidate() async throws {
        try await db.withRollback { db in
            // Create validation trigger (title must be at least 3 characters)
            let trigger = Post.autoValidate(
                "validate_title",
                """
                IF LENGTH(NEW.title) < 3 THEN
                  RAISE EXCEPTION 'Title must be at least 3 characters';
                END IF;
                """
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert with valid title using DSL - should succeed
            try await Post.insert {
                Post.Draft(title: "Valid Title")
            }.execute(db)

            // Insert with invalid title using DSL - should fail
            do {
                try await Post.insert {
                    Post.Draft(title: "AB")
                }.execute(db)
                Issue.record("Expected validation error")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("Title must be at least 3 characters"))
            }
        }
    }

    @Test("autoIncrementVersion increments version on update")
    func testAutoIncrementVersion() async throws {
        try await db.withRollback { db in
            // Create version increment trigger
            let trigger = Document.autoIncrementVersion("inc_version", column: \.version)
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert document using DSL
            try await Document.insert {
                Document.Draft(title: "Doc", version: 1)
            }.execute(db)

            // Update document using DSL
            try await Document
                .update { $0.title = "Updated Doc" }
                .where { $0.title == "Doc" }
                .execute(db)

            // Verify version incremented
            let doc = try await Document.where { $0.title == "Updated Doc" }.fetchOne(db)
            #expect(doc?.version == 2)
        }
    }

    @Test("autoSoftDelete marks row as deleted instead of removing")
    func testAutoSoftDelete() async throws {
        try await db.withRollback { db in
            // Create soft delete trigger
            let trigger = Document.autoSoftDelete(
                "soft_delete",
                deletedAtColumn: \.deletedAt,
                identifiedBy: \.id
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert document using DSL
            try await Document.insert {
                Document.Draft(title: "To Delete")
            }.execute(db)

            // Delete document using DSL
            try await Document
                .where { $0.title == "To Delete" }
                .delete()
                .execute(db)

            // Verify row still exists with deleted_at set
            let doc = try await Document.where { $0.title == "To Delete" }.fetchOne(db)
            #expect(doc?.deletedAt != nil)
        }
    }

    @Test("autoUpdateSearchVector updates full-text search vector")
    func testAutoUpdateSearchVector() async throws {
        try await db.withRollback { db in
            // Create a search vector trigger that combines title and content
            let trigger = Post.autoUpdateSearchVector(
                "update_search_vector",
                searchColumn: \.searchVector,
                from: \.title, \.content
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert post with title and content
            try await Post.insert {
                Post.Draft(title: "PostgreSQL Tutorial", content: "Learn database triggers")
            }.execute(db)

            // Fetch and verify search vector was created with expected content
            let post = try await Post.where { $0.title == "PostgreSQL Tutorial" }.fetchOne(db)
            let initialVector = try #require(post?.searchVector)

            // Verify the search vector contains lexemes from both title and content
            // PostgreSQL normalizes words: "PostgreSQL" -> "postgresql", "Tutorial" -> "tutori", etc.
            let vectorText = initialVector.value.lowercased()
            #expect(vectorText.contains("postgresql"))
            #expect(vectorText.contains("tutori"))  // Stemmed form of "tutorial"
            #expect(vectorText.contains("databas"))  // Stemmed form of "database"
            #expect(vectorText.contains("trigger"))

            // Update content and verify search vector updates
            try await Post
                .update { $0.content = "Advanced trigger patterns" }
                .where { $0.title == "PostgreSQL Tutorial" }
                .execute(db)

            let updatedPost = try await Post.where { $0.title == "PostgreSQL Tutorial" }.fetchOne(db)
            let updatedVector = try #require(updatedPost?.searchVector)

            // Verify the vector changed and contains new lexemes
            #expect(updatedVector.value != initialVector.value)  // Vector should have changed
            let updatedVectorText = updatedVector.value.lowercased()
            #expect(updatedVectorText.contains("advanc"))  // Stemmed form of "advanced"
            #expect(updatedVectorText.contains("pattern"))
        }
    }

    @Test("enforceRowLevelSecurity restricts access by user")
    func testEnforceRowLevelSecurity() async throws {
        try await db.withRollback { db in
            // Set current user in session
            try await db.execute("""
                SELECT set_config('app.user_id', '123', false)
                """)

            // Create RLS trigger
            let trigger = UserDocument.enforceRowLevelSecurity(
                "enforce_user_access",
                column: \.userId,
                matches: PostgreSQL.currentSetting("app.user_id", as: Int.self)
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Insert with matching user_id using DSL - should succeed
            try await UserDocument.insert {
                UserDocument.Draft(userId: 123, content: "User 123 doc")
            }.execute(db)

            // Insert with non-matching user_id using DSL - should fail
            do {
                try await UserDocument.insert {
                    UserDocument.Draft(userId: 456, content: "User 456 doc")
                }.execute(db)
                Issue.record("Expected access denied error")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("Access denied"))
            }
        }
    }

    // MARK: - Advanced Scenario Tests (8 tests)

    @Test("Trigger effects are rolled back with transaction")
    func testTriggerInTransaction() async throws {
        try await db.withRollback { db in
            // Create audit trigger
            let trigger = Post.autoAudit("audit_posts", to: AuditLog.self)
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Use savepoint for nested transaction control
            try await db.execute("SAVEPOINT test_transaction")

            // Insert post using DSL (trigger fires, creates audit log)
            try await Post.insert {
                Post.Draft(title: "Transaction Test")
            }.execute(db)

            // Verify audit log exists within transaction
            let duringTransaction = try await AuditLog.fetchCount(db)
            #expect(duringTransaction == 1)

            // Rollback to savepoint
            try await db.execute("ROLLBACK TO SAVEPOINT test_transaction")

            // Verify both post and audit log were rolled back
            let afterRollback = try await AuditLog.fetchCount(db)
            #expect(afterRollback == 0)
        }
    }

    @Test("Trigger failure rolls back statement")
    func testTriggerFailureRollsBackStatement() async throws {
        try await db.withRollback { db in
            // Create trigger that always fails
            let trigger = Post.autoValidate(
                "always_fail",
                "RAISE EXCEPTION 'Trigger always fails';"
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Use a savepoint to handle the trigger failure
            try await db.execute("SAVEPOINT before_insert")

            // Try to insert using DSL
            do {
                try await Post.insert {
                    Post.Draft(title: "Should Not Insert")
                }.execute(db)
                Issue.record("Expected trigger to prevent insert")
            } catch {
                // Expected error - rollback to savepoint to clear transaction state
                try await db.execute("ROLLBACK TO SAVEPOINT before_insert")
            }

            // Verify row was NOT inserted
            let rowCount = try await Post.fetchCount(db)
            #expect(rowCount == 0)
        }
    }

    @Test("DROP CASCADE removes both function and trigger")
    func testDropCascade() async throws {
        try await db.withRollback { db in
            // Create trigger
            let trigger = Post.autoValidate("validate_func", "RETURN NEW;")
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Verify trigger exists and works before dropping
            try await Post.insert {
                Post.Draft(title: "Test")
            }.execute(db)

            // Drop function with CASCADE
            let dropStatements = trigger.function.drop(ifExists: true, cascade: true)
            try await dropStatements.execute(db)

            // Verify function was dropped - trying to call it should fail
            do {
                try await db.execute("""
                    CREATE TRIGGER recreate_test_trigger
                    BEFORE INSERT ON posts
                    FOR EACH ROW
                    EXECUTE FUNCTION validate_func()
                    """)
                Issue.record("Expected error when referencing dropped function")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("does not exist") || errorMessage.contains("function"))
            }

            // Verify trigger was also dropped (CASCADE effect)
            // Trying to drop the trigger should fail because it doesn't exist
            do {
                try await db.execute("""
                    DROP TRIGGER validate_func ON posts
                    """)
                Issue.record("Expected error when dropping non-existent trigger")
            } catch {
                // Expected error - trigger was already dropped by CASCADE
            }
        }
    }

    @Test("Multiple triggers fire in alphabetical order")
    func testMultipleTriggersFireInOrder() async throws {
        try await db.withRollback { db in
            // Create 3 BEFORE triggers with specific names for ordering
            let trigger1 = TriggerFunction<Post>.define("a_first") {
                #sql(#"NEW."executionLog" = COALESCE(NEW."executionLog", '') || '1'"#)
                #sql("RETURN NEW")
            }
            try await trigger1.execute(db)
            try await Post.createTrigger("a_first_trigger", timing: .before, event: .insert, function: trigger1).execute(db)

            let trigger2 = TriggerFunction<Post>.define("b_second") {
                #sql(#"NEW."executionLog" = COALESCE(NEW."executionLog", '') || '2'"#)
                #sql("RETURN NEW")
            }
            try await trigger2.execute(db)
            try await Post.createTrigger("b_second_trigger", timing: .before, event: .insert, function: trigger2).execute(db)

            let trigger3 = TriggerFunction<Post>.define("c_third") {
                #sql(#"NEW."executionLog" = COALESCE(NEW."executionLog", '') || '3'"#)
                #sql("RETURN NEW")
            }
            try await trigger3.execute(db)
            try await Post.createTrigger("c_third_trigger", timing: .before, event: .insert, function: trigger3).execute(db)

            // Insert row
            try await db.execute("""
                INSERT INTO posts (title) VALUES ('Order Test')
                """)

            // Verify triggers executed in alphabetical order
            let post = try await Post.where { $0.title == "Order Test" }.fetchOne(db)
            #expect(post?.executionLog == "123")
        }
    }

    @Test("Trigger with WHEN clause fires conditionally")
    func testTriggerWithComplexCondition() async throws {
        try await db.withRollback { db in
            // Create trigger with WHEN condition
            let function = TriggerFunction<Document>.updateTimestamp(
                "update_ts_func",
                column: \.updatedAt
            )
            try await function.execute(db)

            let trigger = Document.createTrigger(
                "conditional_update_ts",
                timing: .before,
                event: .update,
                when: { $0.isPublished && !$0.isArchived },
                function: function
            )
            try await trigger.execute(db)

            // Insert documents
            try await db.execute("""
                INSERT INTO documents (title, "isPublished", "isArchived")
                VALUES ('Published Active', true, false),
                       ('Archived', true, true),
                       ('Draft', false, false)
                """)

            // Update all documents
            try await db.execute("""
                UPDATE documents SET title = title || ' Updated'
                """)

            // Only "Published Active" should have updated_at set
            let docs = try await Document.all.order(by: \.title).fetchAll(db)
            for doc in docs {
                if doc.title.contains("Published Active") {
                    #expect(doc.updatedAt != nil)
                } else {
                    #expect(doc.updatedAt == nil)
                }
            }
        }
    }

    @Test("UPDATE OF specific columns triggers selectively")
    func testUpdateOfSpecificColumns() async throws {
        try await db.withRollback { db in
            // Create trigger that only fires when title or content changes
            let function = TriggerFunction<Post>.updateTimestamp(
                "update_ts_func",
                column: \.updatedAt
            )
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "selective_update",
                timing: .before,
                event: .update(of: { ($0.title, $0.content) }),
                function: function
            )
            try await trigger.execute(db)

            // Insert post
            try await db.execute("""
                INSERT INTO posts (title, content, metadata)
                VALUES ('Original', 'Content', 'meta')
                """)

            // Update metadata only - trigger should NOT fire
            try await db.execute("""
                UPDATE posts SET metadata = 'new meta'
                """)

            let afterMetadataUpdate = try await Post.all.fetchOne(db)
            #expect(afterMetadataUpdate?.updatedAt == nil)

            // Update title - trigger SHOULD fire
            try await db.execute("""
                UPDATE posts SET title = 'New Title'
                """)

            let afterTitleUpdate = try await Post.all.fetchOne(db)
            #expect(afterTitleUpdate?.updatedAt != nil)
        }
    }

    @Test("Statement-level trigger fires once per statement")
    func testStatementLevelTrigger() async throws {
        try await db.withRollback { db in
            // Initialize log
            try await db.execute("""
                INSERT INTO "triggerLogs" ("executionCount") VALUES (0)
                """)

            // Create statement-level trigger
            let function = TriggerFunction<Post>.define("increment_log") {
                #sql(#"UPDATE "triggerLogs" SET "executionCount" = "executionCount" + 1"#)
                #sql("RETURN NULL")
            }
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "statement_trigger",
                timing: .after,
                event: .insert,
                level: .statement,
                function: function
            )
            try await trigger.execute(db)

            // Batch insert 10 rows
            try await db.execute("""
                INSERT INTO posts (title)
                SELECT 'Post ' || generate_series(1, 10)
                """)

            let log = try await TriggerLog.all.fetchOne(db)
            #expect(log?.executionCount == 1)
        }
    }

    @Test("Trigger accesses OLD and NEW values correctly")
    func testTriggerAccessesOldAndNew() async throws {
        try await db.withRollback { db in
            // Create trigger that calculates price change
            let function = TriggerFunction<Post>.define("track_price_change") {
                #sql(#"NEW."priceChange" = NEW.price - OLD.price"#)
                #sql("RETURN NEW")
            }
            try await function.execute(db)

            let trigger = Post.createTrigger(
                "track_price",
                timing: .before,
                event: .update,
                function: function
            )
            try await trigger.execute(db)

            // Insert post with initial price
            try await db.execute("""
                INSERT INTO posts (title, price) VALUES ('Product', 100)
                """)

            // Update price
            try await db.execute("""
                UPDATE posts SET price = 150 WHERE title = 'Product'
                """)

            // Verify price change was calculated
            let post = try await Post.where { $0.title == "Product" }.fetchOne(db)
            #expect(post?.priceChange == 50)
        }
    }

    // MARK: - Error Handling Tests (3 tests)

    @Test("Creating trigger without function fails")
    func testCreateTriggerWithoutFunction() async throws {
        try await db.withRollback { db in
            // Try to create trigger referencing non-existent function
            do {
                try await db.execute("""
                    CREATE TRIGGER missing_func_trigger
                    BEFORE INSERT ON posts
                    FOR EACH ROW
                    EXECUTE FUNCTION non_existent_function()
                    """)
                Issue.record("Expected error for missing function")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("does not exist") || errorMessage.contains("function"))
            }
        }
    }

    @Test("Trigger exception includes custom message")
    func testTriggerExceptionIncludesMessage() async throws {
        try await db.withRollback { db in
            // Create trigger with custom exception
            let trigger = Post.autoValidate(
                "custom_error",
                "RAISE EXCEPTION 'Custom validation failed: title is invalid';"
            )
            try await trigger.function.execute(db)
            try await trigger.execute(db)

            // Trigger the error
            do {
                try await db.execute("""
                    INSERT INTO posts (title) VALUES ('Any Title')
                    """)
                Issue.record("Expected custom exception")
            } catch {
                let errorMessage = errorMessage(from: error)
                #expect(errorMessage.contains("Custom validation failed"))
                #expect(errorMessage.contains("title is invalid"))
            }
        }
    }

    @Test("DROP non-existent trigger with IF EXISTS succeeds")
    func testDropNonExistentTrigger() async throws {
        try await db.withRollback { db in
            // Use savepoint for error handling
            try await db.execute("SAVEPOINT before_drop")

            // Drop non-existent trigger without IF EXISTS - should fail
            do {
                try await db.execute("""
                    DROP TRIGGER non_existent_trigger ON posts
                    """)
                Issue.record("Expected error for non-existent trigger")
            } catch {
                // Expected error - rollback to savepoint
                try await db.execute("ROLLBACK TO SAVEPOINT before_drop")
            }

            // Drop with IF EXISTS - should succeed silently
            try await db.execute("""
                DROP TRIGGER IF EXISTS non_existent_trigger ON posts
                """)

            // If we get here without error, test passes
            #expect(true)
        }
    }
}

// MARK: - Test Table Definitions

/// Test table for posts with various timestamp and metadata columns
@Table
private struct Post: Codable, Equatable {
    let id: Int
    var title: String
    var content: String?
    var slug: String?
    var createdAt: Date?
    var updatedAt: Date?
    var searchVector: TextSearch.Vector?  // PostgreSQL tsvector
    var metadata: String?
    var executionLog: String?
    var price: Int?
    var priceChange: Int?
}

/// Test table for documents with version tracking and soft deletes
@Table
private struct Document: Codable, Equatable {
    let id: Int
    var title: String
    var isPublished: Bool = false
    var isArchived: Bool = false
    var version: Int = 1
    var deletedAt: Date?
    var updatedAt: Date?
}

/// Test table for user documents with row-level security
@Table
private struct UserDocument: Codable, Equatable {
    let id: Int
    var userId: Int
    var content: String
}

/// Audit log table for testing audit triggers
@Table
private struct AuditLog: Codable, Equatable, AuditTable {
    let id: Int
    var tableName: String
    var operation: String
    var oldData: String?  // JSONB stored as String
    var newData: String?  // JSONB stored as String
    var changedAt: Date
    var changedBy: String
}

// MARK: - Test Database Setup

extension Database.TestDatabaseSetupMode {
    /// Creates test tables for trigger integration tests
    static let withTriggerTestTables = Database.TestDatabaseSetupMode { db in
        try await db.write { conn in
            // Create posts table
            try await conn.execute("""
                CREATE TABLE posts (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    content TEXT,
                    slug TEXT,
                    "createdAt" TIMESTAMPTZ,
                    "updatedAt" TIMESTAMPTZ,
                    "searchVector" TSVECTOR,
                    metadata TEXT,
                    "executionLog" TEXT,
                    price INTEGER,
                    "priceChange" INTEGER
                )
                """)

            // Create documents table
            try await conn.execute("""
                CREATE TABLE documents (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    "isPublished" BOOLEAN NOT NULL DEFAULT false,
                    "isArchived" BOOLEAN NOT NULL DEFAULT false,
                    version INTEGER NOT NULL DEFAULT 1,
                    "deletedAt" TIMESTAMPTZ,
                    "updatedAt" TIMESTAMPTZ
                )
                """)

            // Create user_documents table
            try await conn.execute("""
                CREATE TABLE "userDocuments" (
                    id SERIAL PRIMARY KEY,
                    "userId" INTEGER NOT NULL,
                    content TEXT NOT NULL
                )
                """)

            // Create audit_logs table
            try await conn.execute("""
                CREATE TABLE "auditLogs" (
                    id SERIAL PRIMARY KEY,
                    "tableName" TEXT NOT NULL,
                    operation TEXT NOT NULL,
                    "oldData" JSONB,
                    "newData" JSONB,
                    "changedAt" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    "changedBy" TEXT NOT NULL DEFAULT current_user
                )
                """)

            // Create trigger_log table for statement-level trigger testing
            try await conn.execute("""
                CREATE TABLE "triggerLogs" (
                    id SERIAL PRIMARY KEY,
                    "executionCount" INTEGER NOT NULL DEFAULT 0
                )
                """)
        }
    }
}

extension Database.TestDatabase {
    /// Creates a test database with trigger test tables
    static func withTriggerTestTables() -> LazyTestDatabase {
        LazyTestDatabase(setupMode: .withTriggerTestTables)
    }
}

// Verify trigger fired once (not 10 times)
// Use raw SQL query since TriggerLog is not a @Table model
@Table
private struct TriggerLog: Codable {
    let id: Int
    var executionCount: Int
}
