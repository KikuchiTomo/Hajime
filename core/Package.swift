// swift-tools-version: 6.1
import PackageDescription

// 層と依存の向きは docs/dev/ARCHITECTURE.md．ここを変えたら
// .claude/skills/s90-architecture/scripts/check_layers.py の ALLOWED も合わせる．
let package = Package(
    name: "S90Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "S90Domain", targets: ["S90Domain"]),
        .library(name: "S90Application", targets: ["S90Application"]),
        .library(name: "S90Engine", targets: ["S90Engine"]),
        .library(name: "S90Persistence", targets: ["S90Persistence"]),
    ],
    dependencies: [
        // fork を revision で固定する(docs/dev/UPSTREAM.md)．
        // Zenzai(文脈を見るニューラルかな漢字変換)の trait を有効にする．モデルは別に置く(docs/dev/adr/0006-zenzai.md)
        .package(
            url: "https://github.com/KikuchiTomo/AzooKeyKanaKanjiConverter",
            revision: "88547906aaafff67e0f0e906cc749a8af43b76e2",
            traits: ["Zenzai"]
        ),
    ],
    targets: [
        .target(name: "S90Domain"),
        .target(name: "S90Application", dependencies: ["S90Domain"]),
        .target(
            name: "S90Engine",
            dependencies: [
                "S90Domain",
                "S90Application",
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ],
            // Zenzai は llama.cpp(C++)を使うので，エンジンを読み込むターゲットは C++ との相互運用を有効にする
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(name: "S90Persistence", dependencies: ["S90Domain", "S90Application"]),
        // 入れずに変換を試す道具(make try)
        .executableTarget(
            name: "s90-playground",
            dependencies: ["S90Domain", "S90Application", "S90Engine", "S90Persistence"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(name: "S90TestSupport", dependencies: ["S90Domain", "S90Application"], path: "Tests/Support"),
        .testTarget(name: "S90DomainTests", dependencies: ["S90Domain"]),
        .testTarget(name: "S90ApplicationTests", dependencies: ["S90Domain", "S90Application", "S90TestSupport"]),
        .testTarget(name: "S90PersistenceTests", dependencies: ["S90Domain", "S90Persistence"]),
        .testTarget(
            name: "S90EngineTests",
            dependencies: ["S90Domain", "S90Application", "S90Engine", "S90TestSupport"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
