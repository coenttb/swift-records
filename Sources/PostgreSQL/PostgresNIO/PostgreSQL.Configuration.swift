#if PostgresNIO
    public import PostgresNIO

    extension PostgreSQL {
        public struct Configuration: Sendable {
            public var host: String
            public var port: Int
            public var username: String
            public var password: String?
            public var database: String
            public var tls: PostgresClient.Configuration.TLS

            public init(
                host: String,
                port: Int,
                username: String,
                password: String?,
                database: String,
                tls: PostgresClient.Configuration.TLS
            ) {
                self.host = host
                self.port = port
                self.username = username
                self.password = password
                self.database = database
                self.tls = tls
            }
        }
    }

    extension PostgreSQL.Configuration {
        public enum Error: Swift.Error, Hashable, Sendable {
            case missing(variable: String)
            case invalidPort(String)
        }

        public init(environment: [String: String], tls: PostgresClient.Configuration.TLS) throws(Error) {
            func value(_ names: String...) throws(Error) -> String {
                guard let value = names.lazy.compactMap({ environment[$0] }).first else {
                    throw .missing(variable: names.joined(separator: " or "))
                }
                return value
            }
            let port = try value("DATABASE_PORT", "POSTGRES_PORT")
            guard let number = Int(port) else { throw .invalidPort(port) }
            self.init(
                host: try value("DATABASE_HOST", "POSTGRES_HOST"),
                port: number,
                username: try value("DATABASE_USER", "POSTGRES_USER"),
                password: environment["DATABASE_PASSWORD"] ?? environment["POSTGRES_PASSWORD"],
                database: try value("DATABASE_NAME", "POSTGRES_DB"),
                tls: tls
            )
        }

        public func client(connections: ClosedRange<Int>) -> PostgresClient.Configuration {
            var configuration = PostgresClient.Configuration(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: tls
            )
            configuration.options.minimumConnections = connections.lowerBound
            configuration.options.maximumConnections = connections.upperBound
            configuration.options.connectionIdleTimeout = .seconds(60)
            configuration.options.keepAliveBehavior = .init(frequency: .seconds(30), query: "SELECT 1")
            return configuration
        }
    }
#endif
