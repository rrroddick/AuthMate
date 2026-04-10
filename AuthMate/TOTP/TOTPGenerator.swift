import Foundation
import CryptoKit

struct TOTPGenerator {
    static func generatePIN(secret: String, time: Date = Date(), window: TimeInterval = 30) throws -> String {
        // Decode the base32 secret
        let keyData = try Base32Decoder.decode(base32String: secret)
        
        // Calculate the counter
        let timeInterval = time.timeIntervalSince1970
        let counter = UInt64(timeInterval / window)
        
        // Convert counter to Big Endian Data
        var counterData = Data(count: 8)
        var c = counter.bigEndian
        withUnsafePointer(to: &c) { ptr in
            counterData.replaceSubrange(0..<8, with: UnsafeRawBufferPointer(start: ptr, count: 8))
        }
        
        // Generate HMAC-SHA1
        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symmetricKey)
        let hash = Data(mac)
        
        // Dynamic Truncation
        let offset = Int(hash.last! & 0x0F)
        
        // Safely extract 4 bytes without unaligned pointer risks
        var truncatedHash = (UInt32(hash[offset]) << 24) |
                            (UInt32(hash[offset + 1]) << 16) |
                            (UInt32(hash[offset + 2]) << 8) |
                            UInt32(hash[offset + 3])
        
        truncatedHash &= 0x7FFFFFFF // Mask highest bit to avoid signed issues
        
        // Compute 6-digit PIN
        let pin = truncatedHash % 1_000_000
        
        // Format to 6 digits with leading zeros
        return String(format: "%06d", pin)
    }
}
