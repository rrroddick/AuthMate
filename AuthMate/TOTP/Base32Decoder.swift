import Foundation

enum Base32Error: Error {
    case invalidCharacters
}

struct Base32Decoder {
    static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    
    static func decode(base32String: String) throws -> Data {
        let string = base32String.replacingOccurrences(of: " ", with: "").uppercased()
        
        var bitString = ""
        for char in string {
            if char == "=" { continue }
            guard let index = base32Alphabet.firstIndex(of: char) else {
                throw Base32Error.invalidCharacters
            }
            let val = base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            let bits = String(val, radix: 2)
            bitString += String(repeating: "0", count: 5 - bits.count) + bits
        }
        
        let length = bitString.count / 8 * 8
        let byteBits = String(bitString.prefix(length))
        
        var data = Data(capacity: length / 8)
        var i = byteBits.startIndex
        while i < byteBits.endIndex {
            let nextIndex = byteBits.index(i, offsetBy: 8)
            let byteString = String(byteBits[i..<nextIndex])
            if let byte = UInt8(byteString, radix: 2) {
                data.append(byte)
            }
            i = nextIndex
        }
        return data
    }

    static func encode(data: Data) -> String {
        var base32String = ""
        var buffer: UInt16 = 0
        var bufferBits: UInt8 = 0
        
        for byte in data {
            buffer = (buffer << 8) | UInt16(byte)
            bufferBits += 8
            
            while bufferBits >= 5 {
                let mask = UInt16(0x1F) << (bufferBits - 5)
                let index = Int((buffer & mask) >> (bufferBits - 5))
                base32String.append(base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: index)])
                bufferBits -= 5
            }
        }
        
        if bufferBits > 0 {
            let index = Int((buffer << (5 - bufferBits)) & 0x1F)
            base32String.append(base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: index)])
        }
        
        return base32String
    }
}
