import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 打鍵が止まったあいだに分岐図の候補を前もって求めても(InputSession.latticeWarmingSteps)，出る分岐図が変わらないことを，本物の変換器で確かめる
@Suite("分岐図の候補を前もって求める")
@MainActor
struct LatticeWarmingTests {
    @Test("前もって求めてから Space を押しても，分岐図と文節を移ったときの分岐図は求めないときと同じ")
    func sameLatticeAfterWarming() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-warming-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "warming", zenzai: nil)
        let settings = FakeSettings()
        func panels(warming: Bool) -> [LatticePanel] {
            let session = InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: FakeCalendar()),
                                       lexicon: FakeLexicon(), settings: settings)
            for key in "kinouhatomodatitoeigawominiittekaerinikissatendekohiwonondekaraiedeyuuhanwotabemasita" {
                _ = session.handle(KeyEvent(.character(key)), context: InputContext())
            }
            _ = session.settle(context: InputContext())
            if warming {
                let steps = session.latticeWarmingSteps
                #expect(steps.count > 1)
                steps.forEach { $0() }
            }
            var result: [LatticePanel] = []
            func collect(_ actions: [ClientAction]) {
                for case .showLattice(let panel) in actions { result.append(panel) }
            }
            collect(session.handle(KeyEvent(.space), context: InputContext()).actions)
            for _ in 0..<result.first.map(\.columns.count).map({ $0 + 1 })! {
                collect(session.handle(KeyEvent(.right), context: InputContext()).actions)
            }
            collect(session.handle(KeyEvent(.right, modifiers: [.shift]), context: InputContext()).actions)
            _ = session.handle(KeyEvent(.escape), context: InputContext())
            _ = session.handle(KeyEvent(.escape), context: InputContext())
            return result
        }
        let plain = panels(warming: false)
        let warmed = panels(warming: true)
        #expect(plain.count > 2)
        #expect(warmed == plain)
    }
}
