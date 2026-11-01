import Foundation

/// 読みで呼び出すコマンド(ランチャー)．読みを変換すると候補の一覧に 1 つ並び，利用者がその候補を選んで確定したときだけ動く．
///
/// 安全のための決まり(docs/dev/SECURITY-MODEL.md)
/// - 何をするかは種類(Action)ごとに決まった形だけ．シェルを通さず，打った文字や候補を引数に差し込まない
/// - 設定の画面で利用者が登録したものだけを使う．同期のファイル・設定の取り込み・入力先のアプリからは書き換えない(SyncGroup.commands)
/// - 第 1 候補(ライブ変換で見える文字)には出さず，Enter で第 1 候補を確定しても動かない
public struct LauncherCommand: Sendable, Equatable, Codable, Hashable, Identifiable {
    /// 何をするか．行き先(target)の意味は種類ごとに決まる
    public enum Kind: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
        /// アプリを開く．macOS はアプリのパス，Windows は実行ファイルのパス
        case openApplication
        /// Web のページを開く(http・https だけ)
        case openURL
        /// ファイルかフォルダを既定のアプリで開く
        case openFile
        /// macOS のショートカット(ショートカット App)を名前で動かす．Windows では使えない
        case runShortcut
    }

    public var id: String
    /// 読み(ひらがな，またはローマ字．ReadingNormalization でそろえる)
    public var reading: String
    /// 候補の一覧に出す名前(「Claude を開く」)
    public var title: String
    public var kind: Kind
    /// 行き先(アプリやファイルのパス，URL，ショートカットの名前)
    public var target: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, reading: String, title: String, kind: Kind, target: String, isEnabled: Bool = true) {
        self.id = id
        self.reading = reading
        self.title = title
        self.kind = kind
        self.target = target
        self.isEnabled = isEnabled
    }

    /// 形の正しいコマンドか．id は UUID，読みと名前は上限の長さ以内，行き先は種類ごとの形
    public var isValid: Bool {
        UUID(uuidString: id) != nil && ReadingNormalization.normalized(reading) != nil
            && !title.trimmingCharacters(in: .whitespaces).isEmpty && title.count <= DefaultSettings.maximumCommandTitleLength
            && !title.contains(where: { $0.isNewline || $0 == "\t" })
            && Self.isValidTarget(target, kind: kind)
    }

    /// 候補の文字列．文字を入れる候補と見分けられるよう，印を付ける(入力中の文字に出る)
    public var candidateText: String { DefaultSettings.commandCandidateMark + title }

    /// 候補の文字列(candidateText)から印を除いた名前．候補の窓では印の代わりにアイコンと札で見せる
    public static func title(ofCandidateText text: String) -> String {
        text.hasPrefix(DefaultSettings.commandCandidateMark) ? String(text.dropFirst(DefaultSettings.commandCandidateMark.count)) : text
    }
}

extension LauncherCommand {
    /// 行き先の形が正しいか．空でなく，上限の長さ以内で，制御文字を含まない．URL は http・https だけ
    public static func isValidTarget(_ value: String, kind: Kind) -> Bool {
        guard !value.isEmpty, value.count <= DefaultSettings.maximumCommandTargetLength,
            !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return false }
        switch kind {
        case .openURL:
            guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
                components.host?.isEmpty == false else { return false }
            return DefaultSettings.commandURLSchemes.contains(scheme)
        case .openApplication, .openFile, .runShortcut:
            return true
        }
    }
}

extension LauncherCommand {
    private enum CodingKeys: String, CodingKey {
        case id, reading, title, kind, target, isEnabled
    }

    /// Windows の設定の画面は一覧の行を id なしで足すので，id が無ければ作る．isEnabled が無ければ使う
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                  reading: try container.decode(String.self, forKey: .reading),
                  title: try container.decode(String.self, forKey: .title),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  target: try container.decode(String.self, forKey: .target),
                  isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true)
    }
}

extension LauncherCommand: CustomStringConvertible, CustomDebugStringConvertible {
    // 読みと行き先は利用者の書いたものなので，ログには長さだけを出す
    public var description: String { "LauncherCommand(readingLength: \(reading.count), titleLength: \(title.count))" }
    public var debugDescription: String { description }
}

/// 読みに当たるコマンドを引く
public enum LauncherCommands {
    /// 読みに当たる，使えるコマンド．読みはローマ字の読みもひらがなにそろえて比べる
    public static func matching(_ reading: String, in commands: [LauncherCommand]) -> [LauncherCommand] {
        commands.filter { $0.isEnabled && $0.isValid && ReadingNormalization.normalized($0.reading) == reading }
    }
}
