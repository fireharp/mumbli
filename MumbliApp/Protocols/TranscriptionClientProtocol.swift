import Foundation

/// Protocol defining the WebSocket transcription client interface.
/// Abstracts communication with the backend /ws/transcribe endpoint.
protocol TranscriptionClientProtocol: AnyObject {
    /// Connect to the transcription WebSocket endpoint with an auth token.
    func connect(authToken: String) async throws

    /// Send a start signal to begin transcription.
    func sendStart() async throws

    /// Send an audio chunk (PCM 16-bit 16kHz mono) to the backend.
    func sendAudio(data: Data) async throws

    /// Send a stop signal to end transcription and trigger polishing.
    func sendStop() async throws

    /// Disconnect from the WebSocket.
    func disconnect()

    /// Called when the server confirms it is listening.
    var onListening: (() -> Void)? { get set }

    /// Called when partial transcription text is available (if supported).
    var onPartial: ((String) -> Void)? { get set }

    /// Called when the final polished text is received.
    var onFinal: ((String) -> Void)? { get set }

    /// Called when an error occurs.
    var onError: ((String) -> Void)? { get set }
}
