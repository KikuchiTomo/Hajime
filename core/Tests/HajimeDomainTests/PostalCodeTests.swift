import Testing
@testable import HajimeDomain

@Suite("郵便番号の読み(R-13)")
struct PostalCodeTests {
    @Test("区切りのある形・無い形・全角を 7 桁の数字にする", arguments: [
        ("100-0001", "1000001", true),
        ("100ー0001", "1000001", true),
        ("１００－０００１", "1000001", true),
        ("1000001", "1000001", false),
    ])
    func query(reading: String, code: String, separated: Bool) {
        #expect(PostalCode.query(for: reading) == .init(code: code, hasSeparator: separated))
    }

    @Test("郵便番号の形でなければ読まない", arguments: ["100-001", "10-00001", "100--0001", "1000-001", "100000a", "12345678"])
    func notPostal(reading: String) {
        #expect(PostalCode.query(for: reading) == nil)
    }
}
