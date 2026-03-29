import Foundation

/// Possible states for the dictation service.
enum DictationState: Equatable {
    case idle
    case listening
    case processing
    case error(String)

    static func == (lhs: DictationState, rhs: DictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Activation mode for dictation.
enum ActivationMode {
    case hold
    case handsFree
}

/// Protocol defining the dictation service interface.
/// Frontend components code against this protocol rather than concrete implementations.
protocol DictationServiceProtocol: AnyObject {
    /// Current state of the dictation service.
    var state: DictationState { get }

    /// Called when the dictation state changes.
    var onStateChanged: ((DictationState) -> Void)? { get set }

    /// Called when final polished text is received.
    var onTextReceived: ((String) -> Void)? { get set }

    /// Called when an error occurs.
    var onError: ((String) -> Void)? { get set }

    /// Start a dictation session with the given activation mode.
    func startDictation(mode: ActivationMode)

    /// Stop the current dictation session and trigger finalization.
    func stopDictation()

    /// Whether dictation is currently active (listening or processing).
    var isActive: Bool { get }
}
