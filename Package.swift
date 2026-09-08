// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AEVYNOShared",
  platforms: [
    .iOS(.v17),
    .tvOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "IPTVCore", targets: ["IPTVCore"]),
    .library(name: "Library", targets: ["Library"]),
    .library(name: "Playback", targets: ["Playback"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "CloudSync", targets: ["CloudSync"]),
    .library(name: "AEVYNOSecurity", targets: ["AEVYNOSecurity"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
  ],
  targets: [
    .target(name: "Domain", path: "Core/Domain"),
    .target(name: "IPTVCore", dependencies: ["Domain"], path: "Core/IPTVCore"),
    .target(name: "Library", dependencies: ["Domain"], path: "Core/Library"),
    .target(name: "Playback", dependencies: ["Domain"], path: "Core/Playback"),
    .target(name: "Persistence", dependencies: ["Domain"], path: "Core/Persistence"),
    .target(name: "CloudSync", dependencies: ["Domain"], path: "Core/CloudSync"),
    .target(name: "AEVYNOSecurity", dependencies: ["Domain"], path: "Core/Security"),
    .target(name: "DesignSystem", dependencies: ["Domain"], path: "DesignSystem"),
    .testTarget(
      name: "LibraryTests",
      dependencies: [
        "Domain",
        "IPTVCore",
        "Library",
        "Playback",
        "Persistence",
        "CloudSync",
        "AEVYNOSecurity",
        "DesignSystem",
      ],
      path: "Tests/LibraryTests"
    ),
  ]
)
