import Foundation

public enum NoiseError: Error, Equatable {
    case badBase64URL
    case handshakeOutOfOrder
    case messageTooShort
    case decryptFailed
    case responderKeyMismatch  // rs != QR k
    case notKeyed
}
