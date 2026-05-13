// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCAnywhere",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CCAnywhere", targets: ["CCAnywhere"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "CCAnywhere",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/CCAnywhere",
            exclude: ["Resources/Info.plist"],
            resources: [
                // (No bundled fonts or assets for now; system fonts used as fallback.)
            ]
        )
    ]
)
