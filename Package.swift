// swift-tools-version:5.3

import PackageDescription

let SwiftDevEnv = Package(
  name: "devenv",
  products: [
    .executable(name: "swift-devenv", targets: ["devenv"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser",
             .revision("8492882b030ad1c8e0bb4ca9d9ce06b07a8150b2")),
    .package(name: "SwiftCOM", url: "https://github.com/compnerd/swift-com",
             .branch("master")),
  ],
  targets: [
    .target(
      name: "devenv",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftCOM", package: "SwiftCOM"),
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
