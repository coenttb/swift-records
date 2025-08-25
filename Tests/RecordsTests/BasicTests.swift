import Testing
import RecordsTestSupport
import Dependencies
import DependenciesTestSupport

@Suite(
    "Basic",
    .dependency(\.envVars, .development),
)
struct BasicTests {
    @Test
    func packageCompiles() async throws {
        // This test just verifies the package compiles
        #expect(true)
    }
    
    @Test
    func configurationFromEnvironment() async throws {
        let config = try Database.Configuration.fromEnvironment()
        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.database == "swift-records-development")
        #expect(config.username == "admin")
    }
}
