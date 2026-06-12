// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CalendarApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "CalendarApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/CalendarApp",
            linkerSettings: [
                // Sparkle.framework 打包时嵌入 App 的 Frameworks 目录
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
