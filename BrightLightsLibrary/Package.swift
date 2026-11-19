// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BrightLightsLibrary",
  platforms: [.macOS("26.0"), .iOS("26.0")],
  products: [
    .library(name: "BrightLightsExtraction", targets: ["BrightLightsExtraction"]),
    .library(name: "BrightLightsSchema", targets: ["BrightLightsSchema"]),
    .library(name: "BrightLightsChecking", targets: ["BrightLightsChecking"])
  ],
  dependencies: [
    .package(path: "../../jon-platform/packages/LLMClientKit"),
    .package(path: "../../jon-platform/Vendor/sqlite-data"),
    .package(path: "../../jon-platform/packages/WebExtractorKit"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "BrightLightsExtraction",
      dependencies: [
        .product(name: "LLMClientKit", package: "LLMClientKit"),
        .product(name: "Dependencies", package: "swift-dependencies")
      ]
    ),
    .target(
      name: "BrightLightsChecking",
      dependencies: [
        "BrightLightsExtraction", "BrightLightsSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "WebExtractorKit", package: "WebExtractorKit"),
        .product(name: "LLMClientKit", package: "LLMClientKit")
      ]
    ),
    .target(
      name: "BrightLightsSchema",
      dependencies: [
        "BrightLightsExtraction",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies")
      ],
      resources: [.copy("Resources/registry.json")]
    ),
    .testTarget(
      name: "BrightLightsExtractionTests",
      dependencies: [
        "BrightLightsExtraction",
        .product(name: "LLMClientKit", package: "LLMClientKit"),
        .product(name: "Dependencies", package: "swift-dependencies")
      ],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "BrightLightsCheckingTests",
      dependencies: [
        "BrightLightsChecking", "BrightLightsSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "LLMClientKit", package: "LLMClientKit")
      ],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "BrightLightsSchemaTests",
      dependencies: [
        "BrightLightsSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
      ]
    )
  ]
)
