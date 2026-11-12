import Carbon
import Foundation
import os

/// 入力ソースの登録を直す補助のアプリ．IME の本体(Hajime.app)の Contents/Helpers に入れ，本体が起動したときと入力先が変わったときに
/// 本体から起動される(InputSourceRegistration)．確かめて，必要なら登録し直して終わる．ここがこのアプリの composition root．
///
/// OS は入れた入力メソッドを入力ソースの一覧から外すことがある(同じバンドル ID のアプリが別の場所に登録されたときなど)．
/// 外れると OS は英字の配列(ABC)で入力させ，キーが IME に届かず，英数・かなのキーでも戻せない．
/// 入力ソースの一覧はサンドボックスの外のプロセスが共有していて，サンドボックスの中の本体からは外れたことが見えず，
/// 本体が登録し直しても共有の一覧には届かない．そのため，サンドボックスの外で動くこのアプリが確かめて登録し直す．
/// キー入力は受け取らず，引数も読まない．登録するのは，このアプリを入れた本体だけ
enum InputSourceHelper {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "men.haji.inputmethod.Hajime.InputSourceHelper", category: "input-source")

    static func run() {
        guard let inputMethod = installedInputMethod(), let identifier = Bundle(url: inputMethod)?.bundleIdentifier else {
            logger.notice("入力メソッドの置き場所(Input Methods)に入っていないので，登録しません")
            return
        }
        guard !isRegistered(identifier) else { return }
        let status = TISRegisterInputSource(inputMethod as CFURL)
        if status == noErr, isRegistered(identifier) {
            logger.notice("入力ソースから外れていたので，登録し直しました")
        } else {
            logger.error("入力ソースから外れていたので登録し直そうとしましたが，失敗しました(\(status, privacy: .public))")
        }
    }

    /// このアプリを入れた入力メソッド(…/Input Methods/Hajime.app)．Input Methods の外(ビルドしたフォルダなど)にあれば nil
    private static func installedInputMethod() -> URL? {
        // Hajime.app/Contents/Helpers/このアプリ.app から 3 つ上がる
        let inputMethod = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard inputMethod.pathExtension == "app", inputMethod.deletingLastPathComponent().lastPathComponent == "Input Methods" else { return nil }
        return inputMethod
    }

    /// OS の入力ソースの一覧(有効にしていないものも含む)に，このバンドル ID の入力ソースがあるか
    private static func isRegistered(_ identifier: String) -> Bool {
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() else { return false }
        return CFArrayGetCount(sources) > 0
    }
}

InputSourceHelper.run()
