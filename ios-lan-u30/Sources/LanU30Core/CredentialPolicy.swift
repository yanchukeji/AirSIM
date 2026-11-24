import Foundation

enum CredentialPolicyError: Error, Equatable {
    case missing
    case tooShort
    case rejectedDefault
}

enum CredentialPolicy {
    static let minimumBytes = 32

    static func material(from text: String) -> Result<[UInt8], CredentialPolicyError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.missing) }
        let lowered = trimmed.lowercased()
        let defaults = ["admin", "password", "123456", "12345678", "root", "airsim", "changeme"]
        if defaults.contains(lowered) { return .failure(.rejectedDefault) }
        if let decoded = Base64URL.decode(trimmed), decoded.count >= minimumBytes, !decoded.allSatisfy({ $0 == 0 }) {
            return .success(decoded)
        }
        let raw = [UInt8](trimmed.utf8)
        guard raw.count >= minimumBytes else { return .failure(.tooShort) }
        guard !raw.allSatisfy({ $0 == 0 }) else { return .failure(.rejectedDefault) }
        return .success(raw)
    }
}
