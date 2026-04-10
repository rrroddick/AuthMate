import Foundation
import Combine
import SwiftUI

@MainActor
class AccountStore: ObservableObject {
    @Published var accounts: [OTPAccount] = []
    private let defaultsKey = "AuthMateAccounts"
    
    init() {
        loadAccounts()
    }
    
    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            if let decoded = try? JSONDecoder().decode([OTPAccount].self, from: data) {
                accounts = decoded.sorted(by: Self.sortComparator)
                reassignColors()
                return
            }
        }
        accounts = []
    }
    
    private func reassignColors() {
        var lastIndex = -1
        for i in 0..<accounts.count {
            let newIndex = CardColorModel.randomIndex(avoiding: lastIndex)
            accounts[i].colorIndex = newIndex
            lastIndex = newIndex
        }
    }
    
    nonisolated private static func sortComparator(_ a: OTPAccount, _ b: OTPAccount) -> Bool {
        let aKey = (a.issuer?.lowercased() ?? a.name.lowercased())
        let bKey = (b.issuer?.lowercased() ?? b.name.lowercased())
        if aKey != bKey { return aKey < bKey }
        return a.name.lowercased() < b.name.lowercased()
    }
    
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
    
    func addAccount(name: String, issuer: String?, secret: String) throws {
        // Validate secret by trying to decode it
        _ = try Base32Decoder.decode(base32String: secret)
        
        let account = OTPAccount(id: UUID(), name: name, issuer: issuer)
        try KeychainManager.saveSecret(secret.replacingOccurrences(of: " ", with: "").uppercased(), for: account.secretReference)
        
        accounts.append(account)
        accounts.sort(by: Self.sortComparator)
        reassignColors()
        saveAccounts()
    }
    
    func parseURI(_ uriString: String) throws {
        guard let url = URLComponents(string: uriString) else {
            throw NSError(domain: "Invalid URI", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Malformed URL format")])
        }
        
        if url.scheme == "otpauth-migration" {
            let accountsRaw = try GoogleAuthMigrationDecoder.decode(uri: uriString)
            guard !accountsRaw.isEmpty else {
                throw NSError(domain: "Empty Migration", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "No accounts found in export")])
            }
            
            for dto in accountsRaw {
                do {
                    try addAccount(name: dto.name, issuer: dto.issuer.isEmpty ? nil : dto.issuer, secret: dto.secret)
                } catch {
                    print("Error importing \(dto.name): \(error)")
                    // Skip invalid entries
                }
            }
            return
        }
        
        guard url.scheme == "otpauth", url.host == "totp" else {
            throw NSError(domain: "Invalid URI", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid URI format. Only otpauth:// or otpauth-migration:// are supported")])
        }
        
        var name = url.path.replacingOccurrences(of: "^/", with: "", options: .regularExpression)
        var issuer: String? = nil
        var secret = ""
        
        if let issuerRanges = name.range(of: ":") {
            issuer = String(name[..<issuerRanges.lowerBound])
            name = String(name[issuerRanges.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        
        url.queryItems?.forEach { item in
            if item.name.lowercased() == "secret", let value = item.value {
                secret = value
            } else if item.name.lowercased() == "issuer", let value = item.value {
                issuer = value
            }
        }
        
        guard !secret.isEmpty else {
            throw NSError(domain: "Missing Secret", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Secret is missing")])
        }
        
        try addAccount(name: name, issuer: issuer, secret: secret)
    }
    
    func delete(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            KeychainManager.deleteSecret(for: account.secretReference)
        }
        accounts.remove(atOffsets: offsets)
        reassignColors()
        saveAccounts()
    }
    
    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        // Do not re-sort after a manual drag — preserve the user-chosen order
        saveAccounts()
    }
}
