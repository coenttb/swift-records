// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-records",
    platforms: [
        .macOS("27"),
        .iOS("27"),
        .tvOS("27"),
        .watchOS("27"),
        .visionOS("27"),
    ],
    products: [
        .library(
            name: "Records",
            targets: ["Records"]
        )
    ],
    dependencies: [
        // L3 — institute-native PostgreSQL-dialect DSL (re-exports L2 Structured
        // Queries). Replaces the pointfreeco swift-structured-queries-postgres fork.
        .package(
            url: "https://github.com/swift-standards/swift-postgresql-standard.git",
            branch: "main"
        ),
        // L2 — identifier/string quoting helpers (FullTextSearch SQL emission).
        .package(
            url: "https://github.com/swift-molecules/swift-structured-queries.git",
            branch: "main"
        ),
        // L2 — `Byte`, the element type of `QueryBinding`'s blob/jsonb payloads and
        // of the `QueryDecoder` blob requirement since the L2 Foundation drain.
        .package(
            url: "https://github.com/swift-molecules/swift-byte.git",
            branch: "main"
        ),
        // L2 — `Instant`, the payload of `QueryBinding.date`/`.dateArray` and of the
        // `QueryDecoder` timestamp requirement since the same drain.
        .package(
            url: "https://github.com/swift-molecules/swift-time.git",
            branch: "main"
        ),
        // L2 — Tagged functor for type-safe SQL identifiers (ChannelName/FunctionName/
        // TriggerName). Replaces pointfreeco/swift-tagged.
        .package(
            url: "https://github.com/swift-atoms/swift-tagged.git",
            branch: "main"
        ),
        // Environment-variable idiom (EnvVars + \.envVars). Formerly ServerFoundationEnvVars (ssf dissolved, W3).
        .package(
            url: "https://github.com/swift-compositions/swift-environment-dependencies.git",
            branch: "main"
        ),
        // Wire execution (PostgresNIO confined to Core/PostgresNIO/ + the config entry points).
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(
            url: "https://github.com/swift-compositions/swift-dependencies.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "Records",
            dependencies: [
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "PostgreSQL Standard Macros", package: "swift-postgresql-standard"),
                .product(
                    name: "Structured Queries Support",
                    package: "swift-structured-queries"
                ),
                // Wire execution is PostgresNIO's, whose column codecs are Foundation
                // types (`Date`, `UUID`, `Data`). The L2 core no longer speaks them,
                // so this opt-in integration supplies the bridges the PostgresNIO
                // boundary needs (`Date.instant`, `Date.init(_ instant:)`,
                // `QueryBinding.UUID.init(_ uuid:)`, `UUID.init?(_ identifier:)`).
                .product(
                    name: "Structured Queries Foundation Integration",
                    package: "swift-structured-queries"
                ),
                .product(name: "Byte", package: "swift-byte"),
                .product(name: "Time", package: "swift-time"),
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(
                    name: "Environment Dependencies",
                    package: "swift-environment-dependencies"
                ),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility")
]

for index in package.targets.indices {
    package.targets[index].swiftSettings = swiftSettings
}
