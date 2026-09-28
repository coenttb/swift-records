#if PostgresNIO
    internal import Foundation
    public import PostgreSQL
    internal import PostgresNIO

    extension PostgreSQL.Configuration {
        public static var test: Self {
            test(environment: ProcessInfo.processInfo.environment)
        }

        public static func test(environment: [String: String]) -> Self {
            Self(
                host: environment["POSTGRES_HOST"] ?? "localhost",
                port: environment["POSTGRES_PORT"].flatMap(Int.init) ?? 5432,
                username: environment["POSTGRES_USER"] ?? "coen",
                password: environment["POSTGRES_PASSWORD"],
                database: environment["POSTGRES_DB"] ?? "swift_postgresql_test",
                tls: .disable
            )
        }
    }
#endif
