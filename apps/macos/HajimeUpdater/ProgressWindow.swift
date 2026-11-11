import AppKit

/// 確認・ダウンロード・検証・インストールのあいだに出す小さな窓．文と進み具合と，取りやめのボタン
@MainActor
final class ProgressWindow {
    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let indicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: UIStrings.cancel, target: nil, action: nil)
    private var onCancel: (() -> Void)?

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.title = UpdaterIdentity.displayName
        window.isReleasedWhenClosed = false
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [label, indicator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        // 余白は OS の標準の間隔の 2 つ分．幅はいちばん長い文が入る大きさにする
        let widest = [UIStrings.checking, UIStrings.downloadingPercent(100), UIStrings.verifying, UIStrings.installing]
            .map { NSTextField(labelWithString: $0).intrinsicContentSize.width }.max() ?? 0
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalToSystemSpacingAfter: content.leadingAnchor, multiplier: 2),
            content.trailingAnchor.constraint(equalToSystemSpacingAfter: stack.trailingAnchor, multiplier: 2),
            stack.topAnchor.constraint(equalToSystemSpacingBelow: content.topAnchor, multiplier: 2),
            content.bottomAnchor.constraint(equalToSystemSpacingBelow: stack.bottomAnchor, multiplier: 2),
            indicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: widest),
        ])
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        window.contentView = content
    }

    /// 文を出す．fraction が nil なら進み具合のわからない動きにする．onCancel が nil ならボタンを隠す
    func show(_ text: String, fraction: Double? = nil, onCancel: (() -> Void)? = nil) {
        label.stringValue = text
        if let fraction {
            indicator.isIndeterminate = false
            indicator.doubleValue = fraction
        } else {
            indicator.isIndeterminate = true
            indicator.startAnimation(nil)
        }
        self.onCancel = onCancel
        cancelButton.isHidden = onCancel == nil
        if !window.isVisible {
            window.setContentSize(window.contentView?.fittingSize ?? .zero)
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        indicator.stopAnimation(nil)
        window.orderOut(nil)
    }

    @objc private func cancel() {
        onCancel?()
    }
}
