// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BrightLightsLibrary",
  platforms: [.macOS("26.0"), .iOS("26.0")],
  products: [
    .library(name: "BrightLightsExtraction", targets: ["BrightLightsExtraction"])
  ],
  dependencies: [
    .package(path: "../../jon-platform/packages/LLMClientKit")
  ],
  targets: [
    .target(
      name: "BrightLightsExtraction",
      dependencies: [
        .product(name: "LLMClientKit", package: "LLMClientKit")
      ]
    ),
    .testTarget(
      name: "BrightLightsExtractionTests",
      dependencies: ["BrightLightsExtraction", .product(name: "LLMClientKit", package: "LLMClientKit")],
      resources: [.copy("Fixtures")]
    )
  ]
)
