import Foundation

/// WebSocket client for the /ws/transcribe endpoint.
/// Implements the protocol from spec section 10.2.
final class TranscriptionClient: TranscriptionClientProtocol {
    var onListening: (() -> Void)?
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func connect(authToken: String) async throws {
        let wsURL = baseURL.appendingPathComponent("ws/transcribe")
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        // First message must be auth per spec section 10.2
        let authMessage: [String: String] = ["type": "auth", "token": authToken]
        let authData = try JSONSerialization.data(withJSONObject: authMessage)
        let authString = String(data: authData, encoding: .utf8)!
        try await webSocketTask?.send(.string(authString))

        // Start listening for server messages
        startReceiving()
    }

    func sendStart() async throws {
        let message: [String: String] = ["type": "start"]
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        try await webSocketTask?.send(.string(string))
    }

    func sendAudio(data: Data) async throws {
        try await webSocketTask?.send(.data(data))
    }

    func sendStop() async throws {
        let message: [String: String] = ["type": "stop"]
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        try await webSocketTask?.send(.string(string))
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving()
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                switch type {
                case "listening":
                    self?.onListening?()
                case "partial":
                    if let text = json["text"] as? String {
                        self?.onPartial?(text)
                    }
                case "final":
                    if let text = json["text"] as? String {
                        self?.onFinal?(text)
                    }
                case "error":
                    if let errorMessage = json["message"] as? String {
                        self?.onError?(errorMessage)
                    }
                default:
                    break
                }
            }
        case .data:
            break
        @unknown default:
            break
        }
    }

    deinit {
        disconnect()
    }
}
