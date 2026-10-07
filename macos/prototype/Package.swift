// swift-tools-version: 6.2
// PROTOTYPE — throwaway. Answers wayfinder #21: what should the native main
// window and settings look like? Fake data only, no real logic. `swift run`.
import PackageDescription

let package = Package(
    name: "YaaglPrototype",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "YaaglPrototype")
    ]
)
