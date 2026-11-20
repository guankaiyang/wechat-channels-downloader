// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ChannelsDownloader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DownloaderCore"),
        .target(name: "AppViews", dependencies: ["DownloaderCore"]),
        .executableTarget(name: "ChannelsDownloader", dependencies: ["DownloaderCore", "AppViews"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore"]),
        .testTarget(name: "AppViewsTests", dependencies: ["AppViews"]),
    ]
)
