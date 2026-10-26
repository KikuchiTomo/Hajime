import AppKit
import ObjectiveC
import os

/// 入力メニューの項目を選んだときに，InputMethodKit の中のどこまで届いたかを記録する(調査用．原因が分かったら消す)．
///
/// InputMethodKit のサーバー(_IMKServerModern)は，メニューを辞書にして入力メニューのプロセスに渡し，
/// 選ばれると項目の名前から動作を探して入力コントローラの doCommandBySelector:commandDictionary: を呼ぶ．
/// その途中のメソッドを差し替えて，呼ばれたことと動作の名前だけを記録する．入力した文字は扱わない
enum MenuDispatchTrace {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "menu-trace")

    static func install() {
        guard let server = NSClassFromString("_IMKServerModern") else {
            logger.notice("_IMKServerModern が無い")
            return
        }
        // 引数がすべてオブジェクトか SEL で，戻り値が void のもの
        // 型は method_getTypeEncoding で確かめたもの(macOS 26)．違う型で差し替えると落ちるので，型の合うものだけ
        for name in ["doCommandBySelector:commandDictionary:client:", "doCommandBySelector:commandDictionary:reply:",
                     "doCommandBySelector:commandDictionary:", "didCommandBySelector:reply:"] {
            traceVoid3(server, name)
        }
        traceBool2(server, "didCommandBySelector:client:")
        traceSelector(server, "_handleCommand:")
        traceVoid4(server, "doCommandBySelector_Common:commandDictionary:clientWrapper:controller:")
        traceObject1(server, "menusDictionary_CommonWithController:")
        traceObject2(server, "_searchSubMenus:forTitle:")
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case nil: return "nil"
        case let dictionary as NSDictionary: return "dict(keys: \(dictionary.allKeys.map { "\($0)" }.sorted()))"
        case let string as String: return "\"\(string)\""
        case let menu as NSMenu: return "menu(\(menu.items.map(\.title)))"
        case let item as NSMenuItem: return "item(\(item.title), action: \(item.action.map(NSStringFromSelector) ?? "nil"))"
        case let object?: return String(describing: type(of: object))
        }
    }

    private static func swap(_ cls: AnyClass, _ name: String, _ make: (IMP) -> AnyObject) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, selector) else {
            logger.notice("無いメソッド: \(name, privacy: .public)")
            return
        }
        let original = method_getImplementation(method)
        method_setImplementation(method, imp_implementationWithBlock(make(original)))
    }

    private static func traceSelector(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, Selector?) -> Void
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, Selector?) -> Void = { this, command in
                logger.notice("\(name, privacy: .public) \(command.map(NSStringFromSelector) ?? "nil", privacy: .public)")
                original(this, NSSelectorFromString(name), command)
            }
            return block as AnyObject
        }
    }

    private static func traceBool2(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, Selector?, AnyObject?) -> Bool
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, Selector?, AnyObject?) -> Bool = { this, command, client in
                let result = original(this, NSSelectorFromString(name), command, client)
                logger.notice("\(name, privacy: .public) \(command.map(NSStringFromSelector) ?? "nil", privacy: .public) -> \(result, privacy: .public)")
                return result
            }
            return block as AnyObject
        }
    }

    private static func traceVoid3(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, Selector?, AnyObject?, AnyObject?) -> Void
        let arity = name.filter { $0 == ":" }.count
        guard arity == 3 || arity == 2 else { return }
        if arity == 2 {
            typealias Fn2 = @convention(c) (AnyObject, Selector, Selector?, AnyObject?) -> Void
            swap(cls, name) { imp in
                let original = unsafeBitCast(imp, to: Fn2.self)
                let block: @convention(block) (AnyObject, Selector?, AnyObject?) -> Void = { this, command, b in
                    logger.notice("\(name, privacy: .public) \(command.map(NSStringFromSelector) ?? "nil", privacy: .public) \(describe(b), privacy: .public)")
                    original(this, NSSelectorFromString(name), command, b)
                }
                return block as AnyObject
            }
            return
        }
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, Selector?, AnyObject?, AnyObject?) -> Void = { this, command, b, c in
                logger.notice("\(name, privacy: .public) \(command.map(NSStringFromSelector) ?? "nil", privacy: .public) \(describe(b), privacy: .public) \(describe(c), privacy: .public)")
                original(this, NSSelectorFromString(name), command, b, c)
            }
            return block as AnyObject
        }
    }

    private static func traceVoid4(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, Selector?, AnyObject?, AnyObject?, AnyObject?) -> Void
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, Selector?, AnyObject?, AnyObject?, AnyObject?) -> Void = { this, command, b, c, d in
                logger.notice("\(name, privacy: .public) \(command.map(NSStringFromSelector) ?? "nil", privacy: .public) controller: \(describe(d), privacy: .public)")
                original(this, NSSelectorFromString(name), command, b, c, d)
            }
            return block as AnyObject
        }
    }

    private static func traceObject1(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, AnyObject?) -> AnyObject? = { this, a in
                let result = original(this, NSSelectorFromString(name), a)
                logger.notice("\(name, privacy: .public) \(describe(a), privacy: .public) -> \(describe(result), privacy: .public)")
                return result
            }
            return block as AnyObject
        }
    }

    private static func traceObject2(_ cls: AnyClass, _ name: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
        swap(cls, name) { imp in
            let original = unsafeBitCast(imp, to: Fn.self)
            let block: @convention(block) (AnyObject, AnyObject?, AnyObject?) -> AnyObject? = { this, a, b in
                let result = original(this, NSSelectorFromString(name), a, b)
                logger.notice("\(name, privacy: .public) \(describe(a), privacy: .public) \(describe(b), privacy: .public) -> \(describe(result), privacy: .public)")
                return result
            }
            return block as AnyObject
        }
    }
}
