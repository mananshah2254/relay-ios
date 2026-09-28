// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OutreachCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "OutreachCore", targets: ["OutreachCore"])],
    targets: [
        .target(name: "OutreachCore"),
        .testTarget(name: "OutreachCoreTests", dependencies: ["OutreachCore"])
    ]
)
