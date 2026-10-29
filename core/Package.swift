// swift-tools-version: 6.1
import PackageDescription

// 層と依存の向きは docs/dev/ARCHITECTURE.md．ここを変えたら
// .claude/skills/hajime-architecture/scripts/check_layers.py の ALLOWED も合わせる．
let package = Package(
    name: "HajimeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HajimeDomain", targets: ["HajimeDomain"]),
        .library(name: "HajimeApplication", targets: ["HajimeApplication"]),
        .library(name: "HajimeEngine", targets: ["HajimeEngine"]),
        .library(name: "HajimePersistence", targets: ["HajimePersistence"]),
    ],
    traits: [
        .trait(name: "Zenzai", description: "Zenzai でかな漢字変換する．llama.cpp が要る"),
        .default(enabledTraits: ["Zenzai"]),
    ],
    dependencies: [
        // fork を revision で固定する(docs/dev/UPSTREAM.md)．
        .package(
            url: "https://github.com/KikuchiTomo/AzooKeyKanaKanjiConverter",
            revision: "c456c0d4dda385107ac48f666d7ee289710fda25",
            traits: [.trait(name: "Zenzai", condition: .when(traits: ["Zenzai"]))]
        ),
    ],
    targets: [
        .target(name: "HajimeDomain"),
        .target(name: "HajimeApplication", dependencies: ["HajimeDomain"]),
        .target(
            name: "HajimeEngine",
            dependencies: [
                "HajimeDomain",
                "HajimeApplication",
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ],
            // Zenzai は llama.cpp(C++)を使うので，エンジンを読み込むターゲットは C++ との相互運用を有効にする
            swiftSettings: [.interoperabilityMode(.Cxx, .when(traits: ["Zenzai"]))]
        ),
        // Windows のスペルチェッカー(ISpellChecker)を呼ぶ C の口．Windows のほかでは何もしない
        .target(name: "CWindowsSpellCheck", linkerSettings: [.linkedLibrary("ole32", .when(platforms: [.windows]))]),
        .target(name: "HajimePersistence", dependencies: [
            "HajimeDomain", "HajimeApplication",
            .target(name: "CWindowsSpellCheck", condition: .when(platforms: [.windows])),
        ]),
        .target(name: "HajimeIPC", dependencies: ["HajimeDomain", "HajimeApplication"]),
        .executableTarget(
            name: "hajime-engine-host",
            dependencies: ["HajimeDomain", "HajimeApplication", "HajimeEngine", "HajimePersistence", "HajimeIPC"],
            swiftSettings: [.interoperabilityMode(.Cxx, .when(traits: ["Zenzai"]))],
            // Windows では窓を持たないプログラムにする．コンソールのプログラムだと，インストーラーやサインインのときの起動で
            // 黒いコンソールの窓が出る(main.swift を使うので入り口は C ランタイムの mainCRTStartup のまま)
            linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"], .when(platforms: [.windows]))]
        ),
        // 入れずに変換を試す道具(make try)
        .executableTarget(
            name: "hajime-playground",
            dependencies: ["HajimeDomain", "HajimeApplication", "HajimeEngine", "HajimePersistence"],
            swiftSettings: [.interoperabilityMode(.Cxx, .when(traits: ["Zenzai"]))]
        ),
        .target(name: "HajimeTestSupport", dependencies: ["HajimeDomain", "HajimeApplication"], path: "Tests/Support"),
        .testTarget(name: "HajimeDomainTests", dependencies: ["HajimeDomain"]),
        .testTarget(name: "HajimeIPCTests", dependencies: ["HajimeDomain", "HajimeApplication", "HajimeIPC", "HajimeTestSupport"]),
        .testTarget(name: "HajimeApplicationTests", dependencies: ["HajimeDomain", "HajimeApplication", "HajimeTestSupport"]),
        // Fixtures は #filePath から読む(古いバージョンの設定のファイル)．リソースとして入れない
        .testTarget(name: "HajimePersistenceTests", dependencies: ["HajimeDomain", "HajimePersistence"], exclude: ["Fixtures"]),
        .testTarget(
            name: "HajimeEngineTests",
            dependencies: ["HajimeDomain", "HajimeApplication", "HajimeEngine", "HajimeTestSupport"],
            swiftSettings: [.interoperabilityMode(.Cxx, .when(traits: ["Zenzai"]))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
