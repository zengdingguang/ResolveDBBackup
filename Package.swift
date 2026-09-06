// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResolveDBBackup",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "ResolveDBBackupCore",
            path: "Sources/ResolveDBBackupCore",
            // 允许自测运行器通过 @testable import 访问 internal 符号
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "ResolveDBBackup",
            dependencies: ["ResolveDBBackupCore"],
            path: "Sources/ResolveDBBackup"
        ),
        // 自测运行器：本机无完整 Xcode（CLT 无 XCTest），用断言跑单元测试。
        // 用法: swift run ResolveDBBackupSelfTests
        .executableTarget(
            name: "ResolveDBBackupSelfTests",
            dependencies: ["ResolveDBBackupCore"],
            path: "Tests/ResolveDBBackupSelfTests"
        )
    ]
)
