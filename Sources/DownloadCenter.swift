import UIKit
import WebKit

extension Notification.Name {
    static let downloadsChanged = Notification.Name("downloadsChanged")
}

struct DownloadRecord: Codable, Identifiable {
    enum State: String, Codable { case running, completed, cancelled, failed }
    let id: UUID
    var name: String
    var received: Int64 = 0
    var expected: Int64 = 0
    var state = State.running
    var destination: URL?
    var error: String?
    var fraction: Double? { expected > 0 ? min(1, max(0, Double(received) / Double(expected))) : nil }
    var detail: String {
        if state == .failed { return error ?? "Download failed" }
        if state == .cancelled { return "Cancelled" }
        let bytes = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        if state == .completed { return "Saved · " + bytes }
        return expected > 0 ? "\(bytes) of \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))" : "Downloading · " + bytes
    }
}

/// Retains WKDownload independently of a tab and emits throttled UI changes.
final class DownloadStore: NSObject, WKDownloadDelegate {
    static let shared = DownloadStore()
    private(set) var records: [DownloadRecord] = []
    private struct Active {
        let id: UUID
        let download: WKDownload
        var observation: NSKeyValueObservation?
    }
    private var active: [ObjectIdentifier: Active] = [:]
    private var pendingChange: DispatchWorkItem?
    private var historyDirty = false
    var runningCount: Int { active.count }
    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "download.history"), let history = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = Array(history.filter { $0.state != .running }.prefix(50))
        }
    }
    func accept(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard active[key] == nil else { return }
        guard active.count < 8 else {
            var rejected = DownloadRecord(id: UUID(), name: download.originalRequest?.url?.lastPathComponent ?? "Download")
            rejected.state = .failed; rejected.error = "Eight downloads are already running. Try again after one finishes."
            records.insert(rejected, at: 0); trim(); changed(persist: true); download.cancel(nil); return
        }
        let id = UUID()
        records.insert(DownloadRecord(id: id, name: download.originalRequest?.url?.lastPathComponent ?? "Download"), at: 0)
        active[key] = Active(id: id, download: download)
        download.delegate = self
        let observation = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self, weak download] progress, _ in
            DispatchQueue.main.async {
                guard let self, let download, let item = self.active[ObjectIdentifier(download)], let index = self.records.firstIndex(where: { $0.id == item.id }) else { return }
                self.records[index].received = progress.completedUnitCount
                self.records[index].expected = progress.totalUnitCount
                self.changed()
            }
        }
        active[key]?.observation = observation
        trim(); changed()
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let item = active[ObjectIdentifier(download)], let index = records.firstIndex(where: { $0.id == item.id }) else { completionHandler(nil); return }
        let leaf = URL(fileURLWithPath: suggestedFilename).lastPathComponent.replacingOccurrences(of: "\0", with: "")
        let safe = leaf.isEmpty || leaf == "." || leaf == ".." ? "Download" : leaf
        let destination = Workspace.downloads.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + safe)
        records[index].name = safe; records[index].destination = destination
        records[index].expected = response.expectedContentLength
        changed(); completionHandler(destination)
    }
    func downloadDidFinish(_ download: WKDownload) {
        complete(download, state: .completed)
        NotificationCenter.default.post(name: Notification.Name("filesChanged"), object: nil)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        complete(download, state: .failed, error: error.localizedDescription)
    }
    func cancel(_ id: UUID) {
        guard let pair = active.first(where: { $0.value.id == id }) else { return }
        let download = pair.value.download
        // Mark before WebKit's failure callback, so cancellation remains distinct.
        complete(download, state: .cancelled)
        download.cancel(nil)
    }
    func clearFinished() { records.removeAll { $0.state != .running }; changed(persist: true) }
    func openDownloads() { Workspace.shared.open(.files, url: Workspace.downloads.absoluteString) }
    private func complete(_ download: WKDownload, state: DownloadRecord.State, error: String? = nil) {
        guard let item = active.removeValue(forKey: ObjectIdentifier(download)), let index = records.firstIndex(where: { $0.id == item.id }) else { return }
        item.observation?.invalidate()
        records[index].state = state; records[index].error = error
        if state == .completed, let destination = records[index].destination {
            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize { records[index].received = Int64(size) }
            records[index].expected = records[index].received
        }
        changed(persist: true)
    }
    private func trim() {
        let running = records.filter { $0.state == .running }
        records = running + Array(records.filter { $0.state != .running }.prefix(max(0, 50 - running.count)))
    }
    private func changed(persist: Bool = false) {
        historyDirty = historyDirty || persist
        guard pendingChange == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; pendingChange = nil
            if historyDirty {
                let finished = records.filter { $0.state != .running }
                if let data = try? JSONEncoder().encode(finished) { UserDefaults.standard.set(data, forKey: "download.history") }
                historyDirty = false
            }
            NotificationCenter.default.post(name: .downloadsChanged, object: nil)
        }
        pendingChange = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

final class DownloadCenterView: UIView, UITableViewDataSource, UITableViewDelegate, DesktopContent {
    var onClose: (() -> Void)?
    private let header = UIStackView()
    private let table = UITableView(frame: .zero, style: .plain)
    private var observation: NSObjectProtocol?
    private var appearanceObservation: NSObjectProtocol?
    private var rows: [DownloadRecord] = []
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesktopStyle.surface; layer.cornerRadius = 16; layer.borderWidth = 1; layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor; clipsToBounds = true
        header.axis = .horizontal; header.alignment = .center
        let title = UILabel(); title.text = "Downloads"; title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = DesktopStyle.text
        header.addArrangedSubview(title)
        header.addArrangedSubview(actionButton("folder", title: nil) { DownloadStore.shared.openDownloads() })
        header.addArrangedSubview(actionButton("checkmark.circle", title: nil) { DownloadStore.shared.clearFinished() })
        header.addArrangedSubview(actionButton("xmark", title: nil) { [weak self] in self?.onClose?() })
        addSubview(header); addSubview(table); table.dataSource = self; table.delegate = self; table.rowHeight = 72
        table.backgroundColor = .clear; table.separatorColor = DesktopStyle.border
        observation = NotificationCenter.default.addObserver(forName: .downloadsChanged, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        appearanceObservation = NotificationCenter.default.addObserver(forName: .appearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.applyAppearance() }
        applyAppearance(); reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) }; if let appearanceObservation { NotificationCenter.default.removeObserver(appearanceObservation) } }
    private func applyAppearance() {
        backgroundColor = DesktopStyle.surface; layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor
        for case let button as UIButton in header.arrangedSubviews {
            button.tintColor = DesktopStyle.text
            if var configuration = button.configuration { configuration.baseForegroundColor = DesktopStyle.text; button.configuration = configuration }
        }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { applyAppearance() }
    }
    override func layoutSubviews() {
        super.layoutSubviews(); header.frame = CGRect(x: 12, y: 4, width: bounds.width - 24, height: 42)
        table.frame = CGRect(x: 0, y: 48, width: bounds.width, height: max(0, bounds.height - 48))
    }
    private func reload() {
        rows = DownloadStore.shared.records; table.reloadData()
        let empty = UILabel(); empty.text = "No downloads yet"; empty.textColor = .secondaryLabel; empty.textAlignment = .center
        table.backgroundView = rows.isEmpty ? empty : nil
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Download") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Download"); let record = rows[indexPath.row]
        cell.accessoryView = nil
        cell.backgroundColor = .clear; cell.textLabel?.text = record.name; cell.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        let percent = record.state == .running ? record.fraction.map { " · \(Int($0 * 100))%" } ?? "" : ""
        cell.detailTextLabel?.text = record.detail + percent; cell.detailTextLabel?.font = .systemFont(ofSize: 11); cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: record.state == .completed ? "checkmark.circle.fill" : record.state == .running ? "arrow.down.circle" : "exclamationmark.circle")
        cell.imageView?.tintColor = record.state == .completed ? .systemGreen : .systemTeal
        if record.state == .running {
            let cancel = UIButton(type: .system); cancel.setImage(UIImage(systemName: "xmark.circle"), for: .normal); cancel.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            cancel.accessibilityLabel = "Cancel " + record.name
            cancel.addAction(UIAction { _ in DownloadStore.shared.cancel(record.id) }, for: .touchUpInside); cell.accessoryView = cancel
        }; return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if rows[indexPath.row].state == .completed { DownloadStore.shared.openDownloads() }
    }
    func pointerClick(at point: CGPoint, secondary: Bool) {
        var hit = hitTest(point, with: nil)
        while let candidate = hit {
            if let button = candidate as? UIButton { button.sendActions(for: .touchUpInside); return }
            hit = candidate.superview
        }
        if let index = table.indexPathForRow(at: convert(point, to: table)) { tableView(table, didSelectRowAt: index) }
    }
    func pointerScroll(at point: CGPoint, delta: CGPoint) {
        let y = min(max(0, table.contentOffset.y + delta.y), max(0, table.contentSize.height - table.bounds.height))
        table.contentOffset.y = y
    }
    func insertText(_ text: String) {}
}
