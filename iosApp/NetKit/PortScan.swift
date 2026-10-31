import Foundation
import Network

/// Main-queue-only, bounded to four simultaneous connections and 64 requested ports.
final class PortScan {
    private let host: String
    private var pending: [UInt16]
    private var active: [UInt16: NWConnection] = [:]
    private var timeouts: [UInt16: DispatchWorkItem] = [:]
    private var handler: ((UInt16?, String?, Bool) -> Void)?
    private var cancelled = false

    init(host: String, ports: [UInt16]) {
        self.host = host
        self.pending = ports.count <= 64 ? Array(Set(ports)).sorted() : []
    }

    func start(_ handler: @escaping (UInt16?, String?, Bool) -> Void) {
        self.handler = handler
        guard !pending.isEmpty else {
            handler(nil, String(localized: "network.invalid"), true)
            return
        }
        fill()
    }

    func cancel() {
        cancelled = true
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        active.values.forEach { $0.cancel() }
        active.removeAll()
        pending.removeAll()
        handler = nil
    }

    private func fill() {
        while !cancelled && active.count < 4 && !pending.isEmpty {
            let port = pending.removeFirst()
            guard let endpoint = NWEndpoint.Port(rawValue: port) else { continue }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpoint, using: .tcp)
            active[port] = connection
            let timeout = DispatchWorkItem { [weak self] in self?.finish(port, key: "network.timeout") }
            timeouts[port] = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.finish(port, key: "lan.open")
                case .waiting(let error):
                    if case .posix(.ECONNREFUSED) = error { self?.finish(port, key: "lan.closed") }
                case .failed(let error):
                    if case .posix(.ECONNREFUSED) = error { self?.finish(port, key: "lan.closed") }
                    else { self?.finish(port, key: "network.failed") }
                default: break
                }
            }
            connection.start(queue: .main)
        }
        if !cancelled && pending.isEmpty && active.isEmpty { handler?(nil, nil, true) }
    }

    private func finish(_ port: UInt16, key: String.LocalizationValue) {
        guard !cancelled, let connection = active.removeValue(forKey: port) else { return }
        timeouts.removeValue(forKey: port)?.cancel()
        connection.cancel()
        handler?(port, String(localized: key), false)
        fill()
    }
}
