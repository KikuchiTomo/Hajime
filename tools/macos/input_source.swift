// 入力メソッドを OS の入力ソースとして有効・無効にする．ログアウトしなくても入力メニューに出し入れするため．
// 使い方: swift tools/macos/input_source.swift enable|disable <.app のパス>
import Carbon
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, ["enable", "disable"].contains(arguments[1]) else {
    print("使い方: swift input_source.swift enable|disable <.app のパス>")
    exit(1)
}
let enable = arguments[1] == "enable"
let appURL = URL(fileURLWithPath: arguments[2])

if enable {
    print("登録: \(TISRegisterInputSource(appURL as CFURL))")
}
let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? ""
let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
let sources = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
for source in sources {
    let id = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue()
    let status = enable ? TISEnableInputSource(source) : TISDisableInputSource(source)
    print("\(enable ? "有効" : "無効") \(id): \(status)")
}
if sources.isEmpty && enable {
    print("入力ソースが見つかりません．一度ログアウトしてログインし直してください")
}
