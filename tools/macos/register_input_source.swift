// 入れた入力メソッドを OS に登録し，有効にする．ログアウトしなくても入力メニューに出るようにするため．
// 使い方: swift tools/macos/register_input_source.swift <.app のパス>
import Carbon
import Foundation

let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let status = TISRegisterInputSource(appURL as CFURL)
print("TISRegisterInputSource: \(status)")

let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? ""
let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
let sources = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
for source in sources {
    let id = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue()
    let enabled = TISEnableInputSource(source)
    print("enable \(id): \(enabled)")
}
if sources.isEmpty {
    print("入力ソースが見つかりません．一度ログアウトしてログインし直してください")
}
