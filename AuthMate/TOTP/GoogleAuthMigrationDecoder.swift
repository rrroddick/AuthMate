import Foundation

struct GoogleAuthMigrationDecoder {
    struct AccountDTO {
        var secret: String
        var name: String
        var issuer: String
    }
    
    static func decode(uri: String) throws -> [AccountDTO] {
        guard let url = URLComponents(string: uri),
              url.scheme == "otpauth-migration",
              let dataItem = url.queryItems?.first(where: { $0.name == "data" }),
              let base64String = dataItem.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?.removingPercentEncoding else {
            throw NSError(domain: "InvalidMigrationURI", code: 1)
        }
        
        // Base64 decoding, fixing missing padding if needed
        var b64 = base64String.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = b64.count % 4
        if padding > 0 {
            b64 += String(repeating: "=", count: 4 - padding)
        }
        
        guard let rawData = Data(base64Encoded: b64) else {
            throw NSError(domain: "InvalidBase64", code: 2)
        }
        
        return parsePayload(data: rawData)
    }
    
    // Minimal Protobuf parser for Google Authenticator Migration Payload
    private static func parsePayload(data: Data) -> [AccountDTO] {
        var accounts: [AccountDTO] = []
        var offset = 0
        
        while offset < data.count {
            guard let tagWire = readVarInt(data: data, offset: &offset) else { break }
            let wireType = tagWire & 0x07
            let tag = tagWire >> 3
            
            if tag == 1 && wireType == 2 {
                // otp_parameters (repeated message OtpParameters)
                guard let length = readVarInt(data: data, offset: &offset) else { break }
                let endOffset = offset + Int(length)
                
                if endOffset <= data.count {
                    if let account = parseOtpParameters(data: data, start: offset, end: endOffset) {
                        accounts.append(account)
                    }
                    offset = endOffset
                }
            } else {
                skipField(data: data, offset: &offset, wireType: Int(wireType))
            }
        }
        
        return accounts
    }
    
    private static func parseOtpParameters(data: Data, start: Int, end: Int) -> AccountDTO? {
        var secret = ""
        var name = ""
        var issuer = ""
        
        var offset = start
        while offset < end {
            guard let tagWire = readVarInt(data: data, offset: &offset) else { break }
            let wireType = Int(tagWire & 0x07)
            let tag = Int(tagWire >> 3)
            
            if wireType == 2 { // Length delimited
                guard let length = readVarInt(data: data, offset: &offset) else { break }
                let fieldEnd = offset + Int(length)
                guard fieldEnd <= end else { break }
                
                let fieldData = data.subdata(in: offset..<fieldEnd)
                if tag == 1 {
                    secret = Base32Decoder.encode(data: fieldData)
                } else if tag == 2 {
                    if let str = String(data: fieldData, encoding: .utf8) { name = str }
                } else if tag == 3 {
                    if let str = String(data: fieldData, encoding: .utf8) { issuer = str }
                }
                
                offset = fieldEnd
            } else {
                skipField(data: data, offset: &offset, wireType: wireType)
            }
        }
        
        guard !secret.isEmpty else { return nil }
        return AccountDTO(secret: secret, name: name.isEmpty ? "Account" : name, issuer: issuer)
    }
    
    private static func readVarInt(data: Data, offset: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
    
    private static func skipField(data: Data, offset: inout Int, wireType: Int) {
        if wireType == 0 {
            _ = readVarInt(data: data, offset: &offset)
        } else if wireType == 1 {
            offset += 8
        } else if wireType == 2 {
            if let len = readVarInt(data: data, offset: &offset) {
                offset += Int(len)
            }
        } else if wireType == 5 {
            offset += 4
        }
    }
}
