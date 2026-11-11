import AppKit
import HajimeDomain
import os

/// 「更新を確認」の流れ(R-19)．最新のバージョンを確かめ，新しければ変更点を見せて更新するかを聞き，
/// 取った配布物を確かめてからインストールする．どこで止まっても入力には影響しない(IME の本体とは別のプロセス)
@MainActor
final class Updater {
    private let installedVersion: ReleaseVersion?
    private let client: UpdateClient
    private let verifier: PackageVerifier
    private let installer: PackageInstaller
    private let progress = ProgressWindow()
    private var download: PackageDownload?
    private var cancelled = false
    private let logger = Logger(subsystem: UpdaterIdentity.subsystem, category: "update")

    init(installedVersion: ReleaseVersion?, client: UpdateClient, verifier: PackageVerifier, installer: PackageInstaller) {
        self.installedVersion = installedVersion
        self.client = client
        self.verifier = verifier
        self.installer = installer
    }

    func run() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HajimeUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try await update(into: folder)
        } catch .cancelled {
            progress.close()
        } catch {
            progress.close()
            logger.notice("更新できませんでした: \(String(describing: error), privacy: .public)")
            showFailure(error)
        }
    }

    private func update(into folder: URL) async throws(UpdateFailure) {
        guard let current = installedVersion else { throw .unreadable }
        progress.show(UIStrings.checking)
        let manifest = try await client.manifest()
        guard manifest.version > current else {
            progress.close()
            inform(UIStrings.upToDate, UIStrings.upToDateDetail(current))
            return
        }
        guard let package = manifest.package(for: .macos, baseURL: DefaultSettings.updateDownloadBaseURL) else { throw .noPackage }
        progress.close()
        guard confirm(manifest.version, current: current, notes: manifest.notes(newerThan: current)) else { return }
        // 開発版(アドホック署名)は配布物の署名と比べられないので，取る前に止める
        guard let team = verifier.ownTeamIdentifier() else { throw .unsignedApp }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .installFailed
        }
        progress.show(UIStrings.downloading, fraction: 0, onCancel: { [weak self] in self?.cancel() })
        let file = try await client.download(package, to: folder, progress: { [weak self] fraction in
            Task { @MainActor in self?.showDownloadProgress(fraction) }
        }, started: { [weak self] download in
            Task { @MainActor in self?.started(download) }
        })
        if cancelled { throw .cancelled }
        progress.show(UIStrings.verifying)
        try await verifier.verify(file, sha256: package.sha256, team: team)
        progress.show(UIStrings.installing)
        try await installer.install(file)
        progress.close()
        logger.notice("v\(manifest.version, privacy: .public) に更新しました")
        inform(UIStrings.updated(manifest.version), UIStrings.updatedDetail)
    }

    private func started(_ download: PackageDownload) {
        self.download = download
        if cancelled { download.cancel() }
    }

    private func cancel() {
        cancelled = true
        download?.cancel()
    }

    private func showDownloadProgress(_ fraction: Double) {
        guard !cancelled else { return }
        progress.show(UIStrings.downloadingPercent(Int((fraction * 100).rounded(.down))), fraction: fraction,
                      onCancel: { [weak self] in self?.cancel() })
    }

    /// 更新するかを聞く．変更点(今のバージョンより新しいもの)は文として選べる欄に出す
    private func confirm(_ version: ReleaseVersion, current: ReleaseVersion, notes: [ReleaseNote]) -> Bool {
        let alert = NSAlert()
        alert.messageText = UIStrings.available(version)
        alert.informativeText = UIStrings.availableDetail(current: current)
        alert.addButton(withTitle: UIStrings.update)
        alert.addButton(withTitle: UIStrings.later)
        if !notes.isEmpty {
            alert.accessoryView = Self.notesView(notes)
        }
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func inform(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }

    private func showFailure(_ failure: UpdateFailure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = UIStrings.failed
        alert.informativeText = UIStrings.detail(failure)
        alert.addButton(withTitle: UIStrings.openDownloadPage)
        alert.addButton(withTitle: UIStrings.close)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: DefaultSettings.latestReleaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 変更点の欄．CHANGELOG.md の節をそのまま文として出す(見出しの「###」は外す)
    private static func notesView(_ notes: [ReleaseNote]) -> NSView {
        let text = notes.map { note in
            let body = note.notes.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.hasPrefix("### ") ? String($0.dropFirst(4)) : String($0) }
                .joined(separator: "\n")
            return UIStrings.noteHeading(note) + "\n\n" + body
        }.joined(separator: "\n\n")
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as? NSTextView
        textView?.isEditable = false
        textView?.string = text
        textView?.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textView?.textContainerInset = NSSize(width: NSFont.smallSystemFontSize / 2, height: NSFont.smallSystemFontSize / 2)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        // 警告の窓の文の幅に合わせ，十数行が見える高さにする
        let lineHeight = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize).boundingRectForFont.height
        scroll.frame = NSRect(x: 0, y: 0, width: lineHeight * 20, height: lineHeight * 12)
        return scroll
    }
}
