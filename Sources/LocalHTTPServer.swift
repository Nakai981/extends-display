import Foundation
import Network

/// Small, bounded HTTP/1.1 server for an explicitly started private-LAN session.
/// Each connection serves one request, then closes. No filesystem paths are served.
final class LocalHTTPServer {
    struct Request {
        let method: String
        let path: String
        let query: [URLQueryItem]
        let headers: [String: String]
        let body: Data
    }
    struct Response {
        var status: Int = 200
        var type: String = "text/plain; charset=utf-8"
        var data: Data
        init(status: Int = 200, type: String = "text/plain; charset=utf-8", data: Data) { self.status = status; self.type = type; self.data = data }
        static func text(_ value: String, status: Int = 200) -> Response { Response(status: status, data: Data(value.utf8)) }
    }
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "extenddesk.http")
    private let handler: (Request, @escaping (Response) -> Void) -> Void
    init(handler: @escaping (Request, @escaping (Response) -> Void) -> Void) { self.handler = handler }
    func start(port: UInt16, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener
            var reported = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if !reported { reported = true; DispatchQueue.main.async { completion(.success(Void())) } }
                case .failed(let error): if !reported { reported = true; DispatchQueue.main.async { completion(.failure(error)) } }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self = self] connection in
                guard let self else { connection.cancel(); return }
                guard self.connections.count < 12 else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection; connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 10) { [weak self = self, weak connection = connection] in connection?.cancel(); self?.connections.removeValue(forKey: id) }
                self.receive(connection, id: id, buffer: Data())
            }; listener.start(queue: queue)
        } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func stop() { queue.async { [self] in listener?.cancel(); listener = nil; connections.values.forEach { $0.cancel() }; connections.removeAll() } }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer; if let data { buffer.append(data) }
            guard buffer.count <= 65536 else { self.send(.text("Request too large", status: 413), to: connection, id: id); return }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)), let header = String(data: buffer[..<range.lowerBound], encoding: .utf8) {
                let lines = header.components(separatedBy: "\r\n")
                let parts = (lines.first ?? "").split(separator: " ")
                guard parts.count == 3, parts[2] == "HTTP/1.1", ["GET", "POST"].contains(String(parts[0])) else { self.send(.text("Bad request", status: 400), to: connection, id: id); return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].lowercased()
                    guard headers[key] == nil else { self.send(.text("Duplicate header", status: 400), to: connection, id: id); return }
                    headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= 32768 else { self.send(.text("Bad length", status: 400), to: connection, id: id); return }
                let body = buffer[range.upperBound...]
                if body.count >= length {
                    guard let components = URLComponents(string: "http://localhost" + String(parts[1])) else { self.send(.text("Bad URL", status: 400), to: connection, id: id); return }
                    let request = Request(method: String(parts[0]), path: components.path, query: components.queryItems ?? [], headers: headers, body: Data(body.prefix(length)))
                    DispatchQueue.main.async { self.handler(request) { response in self.queue.async { self.send(response, to: connection, id: id) } } }; return
                }
            }
            if complete || error != nil { connection.cancel(); self.connections.removeValue(forKey: id) }
            else { self.receive(connection, id: id, buffer: buffer) }
        }
    }
    private func send(_ response: Response, to connection: NWConnection, id: UUID) {
        let reason = response.status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.type)\r\nContent-Length: \(response.data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'\r\n\r\n"
        connection.send(content: Data(header.utf8) + response.data, completion: .contentProcessed { [weak self] _ in connection.cancel(); self?.connections.removeValue(forKey: id) })
    }
}

enum LANViewer {
    static let html = """
    <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>ExtendDesk LAN Viewer</title><style>body{margin:0;background:#0b1120;color:white;font:15px system-ui}header{padding:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}button,input{padding:10px;border-radius:8px;border:0}img{display:block;max-width:100%;max-height:80vh;margin:auto;touch-action:none}#status{color:#a5b4fc}</style>
    <header><strong>ExtendDesk · Private LAN</strong><input id="text" placeholder="Text to send"><button id="send">Send</button><button id="enter">Enter</button><button id="back">Backspace</button><span id="status">Connecting…</span></header><img id="screen" alt="Desktop screen">
    <script>
    const token=new URLSearchParams(location.search).get('token');history.replaceState(null,'',location.pathname);
    const screen=document.getElementById('screen'),status=document.getElementById('status');let previous=null,busy=false;
    async function action(payload){try{const r=await fetch('/input',{method:'POST',headers:{'Content-Type':'application/json','X-ExtendDesk-Token':token},body:JSON.stringify(payload)});if(!r.ok)throw Error(r.status);status.textContent='Connected';}catch(e){status.textContent='Control failed: '+e.message;}}
    async function refresh(){try{const r=await fetch('/frame',{headers:{'X-ExtendDesk-Token':token}});if(!r.ok)throw Error(r.status);const url=URL.createObjectURL(await r.blob());screen.src=url;if(previous)URL.revokeObjectURL(previous);previous=url;status.textContent='Connected · preview quality';}catch(e){status.textContent='Disconnected: '+e.message;}setTimeout(refresh,250);}refresh();
    function pos(e){const r=screen.getBoundingClientRect();return {x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))};}
    screen.onclick=e=>action({kind:'click',...pos(e)});screen.oncontextmenu=e=>{e.preventDefault();action({kind:'right',...pos(e)});};
    screen.onwheel=e=>{e.preventDefault();if(!busy){busy=true;action({kind:'scroll',...pos(e),dx:e.deltaX,dy:e.deltaY}).finally(()=>busy=false);} };
    document.getElementById('send').onclick=()=>{action({kind:'text',text:document.getElementById('text').value});document.getElementById('text').value='';};
    document.getElementById('enter').onclick=()=>action({kind:'text',text:'\\n'});document.getElementById('back').onclick=()=>action({kind:'text',text:'\\b'});
    </script></html>
    """
}
