// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QRScanner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QRScanner",
            path: "Sources/QRScanner",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/QRScanner/Info.plist",
                             ]),
            ]
        )
    ]
)
