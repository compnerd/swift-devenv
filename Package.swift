// swift-tools-version:5.3

import PackageDescription

let SwiftDevEnv = Package(
  name: "devenv",
  products: [
    .executable(name: "swift-devenv", targets: ["devenv"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser",
             .upToNextMinor(from: "0.3.0")),
  ],
  targets: [
    .target(
      name: "devenv",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .unsafeFlags(["-parse-as-library"]),
      ],
      linkerSettings: [
        .linkedLibrary("Pathcch.lib"),
      ]
    )
  ]
)
