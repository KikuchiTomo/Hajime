import Foundation
import HajimeDomain
@testable import HajimeEngine
import Testing

/// 設定の「Zenzai のモデル」で，打鍵が止まったとき・変換と，打っている間の表示に使うモデルが決まることを確かめる．
/// モデルのファイルは読まない(どのモデルを選ぶかだけを見る)
@Suite("Zenzai のモデルの選び方")
@MainActor
struct ZenzaiChoiceTests {
    private let small = ZenzaiModel(url: URL(fileURLWithPath: "/models/\(ZenzaiModel.Variant.small.fileName)"))
    private let xsmall = ZenzaiModel(url: URL(fileURLWithPath: "/models/\(ZenzaiModel.Variant.xsmall.fileName)"))

    private func makeEngine(zenzai: ZenzaiModel?, fastZenzai: ZenzaiModel?, choice: ZenzaiModelChoice) throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-choice-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "choice", zenzai: zenzai, fastZenzai: fastZenzai)
        var settings = Settings()
        settings.zenzaiModel = choice
        engine.apply(settings)
        return engine
    }

    @Test("既定は精度を優先し，small だけを使う")
    func defaultIsAccurate() throws {
        #expect(Settings().zenzaiModel == .accurate)
        let engine = try makeEngine(zenzai: small, fastZenzai: xsmall, choice: .accurate)
        #expect(engine.zenzai == small)
        #expect(engine.typingZenzai == nil)
    }

    @Test("速さを優先すると xsmall だけを使う")
    func fast() throws {
        let engine = try makeEngine(zenzai: small, fastZenzai: xsmall, choice: .fast)
        #expect(engine.zenzai == xsmall)
        #expect(engine.typingZenzai == nil)
    }

    @Test("併用では，打っている間は xsmall，打鍵が止まったときと変換は small を使う")
    func combined() throws {
        let engine = try makeEngine(zenzai: small, fastZenzai: xsmall, choice: .combined)
        #expect(engine.zenzai == small)
        #expect(engine.typingZenzai == xsmall)
    }

    @Test("xsmall が無ければ，どれを選んでも small だけを使う", arguments: ZenzaiModelChoice.allCases)
    func withoutFastModel(choice: ZenzaiModelChoice) throws {
        let engine = try makeEngine(zenzai: small, fastZenzai: nil, choice: choice)
        #expect(engine.zenzai == small)
        #expect(engine.typingZenzai == nil)
    }

    @Test("small が無ければ，どれを選んでも xsmall だけを使う", arguments: ZenzaiModelChoice.allCases)
    func withoutAccurateModel(choice: ZenzaiModelChoice) throws {
        let engine = try makeEngine(zenzai: nil, fastZenzai: xsmall, choice: choice)
        #expect(engine.zenzai == xsmall)
        #expect(engine.typingZenzai == nil)
    }

    @Test("設定のファイルに書いて読み直しても選んだモデルが残り，項目が無い古いファイルは精度を優先にする")
    func persistence() throws {
        var settings = Settings()
        settings.zenzaiModel = .combined
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.zenzaiModel == .combined)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).zenzaiModel == .accurate)
    }
}
