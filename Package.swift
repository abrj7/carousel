// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Carousel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Carousel", targets: ["Carousel"]),
    ],
    targets: [
        // Pure layout model: no AppKit, no Accessibility. Everything here is unit tested.
        .target(name: "CarouselCore"),
        // The app: Accessibility window control, hotkeys, overlays, menu bar.
        .executableTarget(
            name: "Carousel",
            dependencies: ["CarouselCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "CarouselCoreTests", dependencies: ["CarouselCore"]),
    ]
)
