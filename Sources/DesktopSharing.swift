import UIKit
import Darwin

@MainActor
final class DesktopSharing {
    static let shared = DesktopSharing()
    private var server: LocalHTTPServer?
    private var token = ""
    private(set) var running = false
    private var starting = false
    private var cachedFrame: Data?
    private var capturedAt = Date.distantPast
    private var frameInFlight = false
    private var frameWaiters: [(LocalHTTPServer.Response) -> Void] = []
    private var generation = 0
    private let encodingQueue = DispatchQueue(label: "extenddesk.jpeg", qos: .userInitiated)
    var connectionInfo: String { "http://\(Self.address()):8765/?token=\(token)" }
    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !running else { completion(.success(Void())); return }
        guard !starting else { completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "Sharing is already starting."]))); return }
        generation += 1; let requestGeneration = generation; starting = true
        token = UUID().uuidString + UUID().uuidString
        let server = LocalHTTPServer { [weak self] request, reply in self?.handle(request, reply: reply) }
        self.server = server
        server.start(port: 8765) { [weak self] result in
            guard let self, generation == requestGeneration else { completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "Sharing stopped."]))); return }
            starting = false
            switch result {
            case .success: running = true
            case .failure: server.stop(); self.server = nil; token = ""
            }
            completion(result)
        }
    }
    func stop() {
        generation += 1; server?.stop(); server = nil; running = false; starting = false; token = ""
        cachedFrame = nil; capturedAt = .distantPast; frameInFlight = false
        let pending = frameWaiters; frameWaiters.removeAll(); pending.forEach { $0(.text("Sharing stopped", status: 503)) }
    }
    private func frame(from desktop: DesktopController, reply: @escaping (LocalHTTPServer.Response) -> Void) {
        if let cachedFrame, Date().timeIntervalSince(capturedAt) < 0.25 { reply(.init(type: "image/jpeg", data: cachedFrame)); return }
        frameWaiters.append(reply)
        guard !frameInFlight else { return }
        frameInFlight = true; let requestGeneration = generation
        desktop.snapshot { [weak self] image in
            self?.encodeFrame(image, generation: requestGeneration)
        }
    }
    private func encodeFrame(_ image: UIImage?, generation requestGeneration: Int) {
        // The worker captures immutable image data and a weak-owner completion;
        // it never implicitly promotes the service to a strong capture.
        let completed: (Data?) -> Void = { [weak self] data in
            self?.finishFrame(data, generation: requestGeneration)
        }
        encodingQueue.async { [image, completed] in
            let data = image?.jpegData(compressionQuality: 0.6)
            DispatchQueue.main.async { completed(data) }
        }
    }
    private func finishFrame(_ data: Data?, generation requestGeneration: Int) {
        guard generation == requestGeneration else { return }
        frameInFlight = false; cachedFrame = data; capturedAt = Date()
        let pending = frameWaiters; frameWaiters.removeAll()
        let response = data.map { LocalHTTPServer.Response(type: "image/jpeg", data: $0) } ?? .text("Capture unavailable", status: 503)
        pending.forEach { $0(response) }
    }
    private func handle(_ request: LocalHTTPServer.Request, reply: @escaping (LocalHTTPServer.Response) -> Void) {
        let supplied = request.headers["x-extenddesk-token"] ?? request.query.first(where: { $0.name == "token" })?.value
        guard !token.isEmpty, supplied == token else { reply(.text("Unauthorized", status: 401)); return }
        if request.method == "GET", request.path == "/" { reply(.init(type: "text/html; charset=utf-8", data: Data(LANViewer.html.utf8))); return }
        guard let desktop = Workspace.shared.activeDesktop else { reply(.text("No desktop", status: 503)); return }
        if request.method == "GET", request.path == "/frame" {
            frame(from: desktop, reply: reply); return
        }
        if request.method == "POST", request.path == "/input", request.headers["x-extenddesk-token"] == token,
           let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], let kind = object["kind"] as? String {
            if let x = object["x"] as? Double, let y = object["y"] as? Double, x.isFinite, y.isFinite {
                desktop.setPointer(normalized: CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y))))
            }
            switch kind {
            case "click": desktop.click()
            case "right": desktop.click(secondary: true)
            case "scroll":
                let dx = object["dx"] as? Double ?? 0, dy = object["dy"] as? Double ?? 0
                guard dx.isFinite, dy.isFinite else { reply(.text("Invalid coordinates", status: 400)); return }
                desktop.scroll(CGPoint(x: min(1000, max(-1000, dx)), y: min(1000, max(-1000, dy))))
            case "text": desktop.type(String((object["text"] as? String ?? "").prefix(4096)))
            default: reply(.text("Unknown action", status: 400)); return
            }; reply(.text("OK")); return
        }; reply(.text("Not found", status: 404))
    }
    static func address() -> String {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return "IPHONE-LAN-IP" }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let interface = item.pointee
            if String(cString: interface.ifa_name) == "en0", let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
            }; cursor = interface.ifa_next
        }; return "IPHONE-LAN-IP"
    }
}
