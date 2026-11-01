import SwiftUI
import AppKit
import ScreenCaptureKit
import ApplicationServices

@main
struct LinkApp: App {
    @StateObject private var model = LinkModel()
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 18) {
                Label("ExtendDesk Link", systemImage: "display.2").font(.largeTitle)
                Text("Share the main Mac display with your iPhone or iPad on a trusted private network. Preview transport: JPEG, up to 4 frames/sec, no audio.")
                Text("Traffic is not encrypted. Anyone with the session URL can view and control this Mac while sharing is on.").foregroundStyle(.secondary)
                HStack {
                    Button("Screen recording permission") { CGRequestScreenCaptureAccess() }
                    Button("Accessibility permission") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                }
                HStack {
                    Button(model.running ? "Stop sharing" : "Start sharing") { model.running ? model.stop() : model.start() }
                    if model.running { Button("Copy session URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.url, forType: .string) } }
                }
                Text(model.message).textSelection(.enabled)
                if model.running {
                    Text("Replace MAC-LAN-IP with this Mac’s Wi-Fi IP address (System Settings → Wi-Fi → Details → TCP/IP). Open the URL in ExtendDesk’s browser, then use Web on device for direct interaction if needed.").font(.caption)
                }
            }.padding(28).frame(width: 650)
        }
    }
}

final class LinkModel: ObservableObject {
    @Published var running = false
    @Published var message = "Stopped. Grant permissions before starting."
    @Published var url = ""
    private var token = ""
    private var server: LocalHTTPServer?
    private var frame: Data?
    private var capturing = false
    private var capturedAt = Date.distantPast
    func start() {
        guard CGPreflightScreenCaptureAccess() else { message = "Screen recording permission required. Grant permission, then restart the app if macOS asks."; return }
        token = UUID().uuidString + UUID().uuidString
        let server = LocalHTTPServer { [weak self] request, reply in self?.handle(request, reply: reply) }
        self.server = server
        server.start(port: 8766) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: running = true; url = "http://MAC-LAN-IP:8766/?token=\(token)"; message = url
            case .failure(let error): message = error.localizedDescription
            }
        }
    }
    func stop() { server?.stop(); server = nil; running = false; token = ""; frame = nil; message = "Stopped" }
    private func handle(_ request: LocalHTTPServer.Request, reply: @escaping (LocalHTTPServer.Response) -> Void) {
        let supplied = request.headers["x-extenddesk-token"] ?? request.query.first(where: { $0.name == "token" })?.value
        guard !token.isEmpty, supplied == token else { reply(.text("Unauthorized", status: 401)); return }
        if request.path == "/", request.method == "GET" { reply(.init(type: "text/html; charset=utf-8", data: Data(LANViewer.html.utf8))); return }
        if request.path == "/frame", request.method == "GET" {
            if let frame, Date().timeIntervalSince(capturedAt) < 0.25 || capturing { reply(.init(type: "image/jpeg", data: frame)); return }
            guard !capturing else { reply(.text("Capture busy", status: 503)); return }
            capturing = true
            Task { @MainActor in
                defer { self.capturing = false }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { reply(.text("No display", status: 503)); return }
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration(); config.width = min(1600, display.width); config.height = Int(Double(config.width) * Double(display.height) / Double(display.width)); config.showsCursor = true
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { reply(.text("JPEG unavailable", status: 503)); return }
                    self.frame = data; self.capturedAt = Date(); reply(.init(type: "image/jpeg", data: data))
                } catch { reply(.text(error.localizedDescription, status: 503)) }
            }; return
        }
        if request.path == "/input", request.method == "POST", request.headers["x-extenddesk-token"] == token,
           let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], let kind = object["kind"] as? String {
            guard AXIsProcessTrusted() else { reply(.text("Accessibility permission required", status: 403)); return }
            let bounds = CGDisplayBounds(CGMainDisplayID())
            let x = object["x"] as? Double ?? 0, y = object["y"] as? Double ?? 0
            guard x.isFinite, y.isFinite else { reply(.text("Bad coordinates", status: 400)); return }
            let point = CGPoint(x: bounds.minX + min(1, max(0, x)) * bounds.width, y: bounds.minY + min(1, max(0, y)) * bounds.height)
            switch kind {
            case "click", "right":
                let right = kind == "right"
                CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseDown : .leftMouseDown, mouseCursorPosition: point, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
                CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseUp : .leftMouseUp, mouseCursorPosition: point, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
            case "scroll":
                let dx = object["dx"] as? Double ?? 0, dy = object["dy"] as? Double ?? 0
                guard dx.isFinite, dy.isFinite else { reply(.text("Bad scroll", status: 400)); return }
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(min(1000, max(-1000, -dy))), wheel2: Int32(min(1000, max(-1000, -dx))), wheel3: 0)?.post(tap: .cghidEventTap)
            case "text":
                let text = String((object["text"] as? String ?? "").prefix(4096))
                if text == "\n" || text == "\u{8}" {
                    let code: CGKeyCode = text == "\n" ? 36 : 51
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
                    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
                } else {
                    let units = Array(text.utf16)
                    for down in [true, false] {
                        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) {
                            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }; event.post(tap: .cghidEventTap)
                        }
                    }
                }
            default: reply(.text("Unknown action", status: 400)); return
            }; reply(.text("OK")); return
        }; reply(.text("Not found", status: 404))
    }
}
