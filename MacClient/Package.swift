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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        // Markdown 渲染（GFM + 代码块 + 表格 + 链接 + 图片）
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        // 代码语法高亮（highlight.js 内核，192 种语言）
        .package(url: "https://github.com/raspu/Highlightr", from: "2.2.0")
    ],
    targets: [
        .executableTarget(
            name: "CCAnywhere",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr")
            ],
            path: "Sources/CCAnywhere",
            exclude: ["Resources/Info.plist"],
            resources: [
                // hook bridge Python 脚本（由 HookBridgeDeployer 在启动时从 bundle 复制到
                // ~/Library/Application Support/cc-anywhere/bin/ 并 chmod 0755）。
                .copy("Resources/cc-anywhere-hook-bridge.py")
            ]
        )
    ]
)
