import Foundation

/// 変換マクロの形を，バージョン 13 までに保存した一覧に足す(SettingsSchema のバージョン 13 → 14)．
///
/// 足す形(DefaultSettings.addedMacros)は無効のまま末尾に足し，使う形だけを利用者が設定の画面でオンにする．
/// 一覧を書いていない設定は，読むときに今の既定の一覧になる．同じ id の形がすでにあれば足さない(利用者が消した既定の形は戻さない)
enum MacroPresetUpgrade {
    static func upgrade(_ object: inout [String: JSONValue]) {
        guard case .array(var macros)? = object["macros"] else { return }
        let ids = Set(macros.compactMap { macro -> String? in
            guard case .object(let fields) = macro, case .string(let id)? = fields["id"] else { return nil }
            return id
        })
        for macro in DefaultSettings.addedMacros where !ids.contains(macro.id) && macros.count < DefaultSettings.maximumMacros {
            guard let data = try? JSONEncoder().encode(macro), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            macros.append(value)
        }
        object["macros"] = .array(macros)
    }
}
