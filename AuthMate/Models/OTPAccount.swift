import Foundation

struct OTPAccount: Identifiable, Codable {
    var id: UUID
    var name: String
    var issuer: String?
    
    // Transient: not persisted, reassigned on every launch or account addition
    var colorIndex: Int = -1
    
    // Custom reference to the secret stored in the Keychain.
    // The secret is never stored in UserDefaults.
    var secretReference: String {
        return "TOTP-Secret-\(id.uuidString)"
    }
    
    // Exclude colorIndex from JSON serialization
    private enum CodingKeys: String, CodingKey {
        case id, name, issuer
    }
}
