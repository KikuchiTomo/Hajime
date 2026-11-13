import HajimeDomain
import Testing

/// 起動のときに確かめた結果の記録(ADR 0017)は，同じ形・同じアプリのバージョンで書いたものだけを使う
@Suite("確かめた結果の記録")
struct VerificationRecordTests {
    private let entry = VerificationRecord.Entry(location: "/a", expectedSHA256: String(repeating: "a", count: 64), files: "x")

    @Test("同じアプリのバージョンの記録だけを使う")
    func sameVersion() {
        let record = VerificationRecord(appVersion: "1.0 (1)", entries: ["zenzai.small": entry])
        #expect(record.entries(for: "1.0 (1)") == ["zenzai.small": entry])
        #expect(record.entries(for: "1.0 (2)").isEmpty)
        #expect(record.entries(for: "").isEmpty)
    }

    @Test("形の番号が違う記録は使わない")
    func otherFormat() {
        var record = VerificationRecord(appVersion: "1", entries: ["dictionary": entry])
        record.format = VerificationRecord.currentFormat + 1
        #expect(record.entries(for: "1").isEmpty)
    }

    @Test("属性のどれかが違えば，まとめた値が変わる．渡す順にはよらない")
    func digest() {
        let stamp = FileStamp(size: 3, modified: 100, volume: 1, file: 2)
        let base = FileStamp.digest(of: [(name: "a", stamp: stamp), (name: "b", stamp: stamp)])
        #expect(FileStamp.digest(of: [(name: "b", stamp: stamp), (name: "a", stamp: stamp)]) == base)
        for changed in [FileStamp(size: 4, modified: 100, volume: 1, file: 2), FileStamp(size: 3, modified: 101, volume: 1, file: 2),
                        FileStamp(size: 3, modified: 100, volume: 9, file: 2), FileStamp(size: 3, modified: 100, volume: 1, file: 9)] {
            #expect(FileStamp.digest(of: [(name: "a", stamp: changed), (name: "b", stamp: stamp)]) != base)
        }
        #expect(FileStamp.digest(of: [(name: "c", stamp: stamp), (name: "b", stamp: stamp)]) != base)
    }
}
