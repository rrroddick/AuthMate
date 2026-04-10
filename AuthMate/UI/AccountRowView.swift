import SwiftUI
import Combine

struct AccountRowView: View {
    let account: OTPAccount
    
    @State private var pin: String = "------"
    @State private var timeRemaining: Double = 30.0
    @State private var progress: Double = 1.0
    @State private var showCopied: Bool = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var formattedPin: String {
        guard pin.count == 6 else { return pin }
        let index = pin.index(pin.startIndex, offsetBy: 3)
        return "\(pin[..<index]) \(pin[index...])"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(String((account.issuer ?? account.name).prefix(1)).uppercased())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .offset(y: -8)
            
            VStack(alignment: .leading, spacing: 8) {
                // Identifiers
                VStack(alignment: .leading, spacing: 2) {
                    // Issuer shown first and larger (falls back to name if absent)
                    if let issuer = account.issuer, !issuer.isEmpty {
                        Text(issuer)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(account.name)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text(account.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                
                // Code and Timer directly underneath
                HStack(alignment: .center) {
                    Text(formattedPin)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        CircularProgressView(progress: progress, color: timeRemaining <= 5 ? .red : .white)
                            .frame(width: 14, height: 14)
                        Text("\(Int(timeRemaining))s")
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundColor(timeRemaining <= 5 ? .red : .white.opacity(0.8))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(CardColorModel.color(for: account.colorIndex))
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onTapGesture {
            copyToClipboard()
        }
        .overlay {
            if showCopied {
                Color.black.opacity(0.6)
                    .cornerRadius(20)
                    .overlay {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Copied!")
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onReceive(timer) { _ in
            updateTOTP()
        }
        .onAppear {
            updateTOTP()
        }
    }
    
    private func updateTOTP() {
        let now = Date()
        let interval = 30.0
        let currentSecond = now.timeIntervalSince1970.truncatingRemainder(dividingBy: interval)
        timeRemaining = interval - currentSecond
        progress = timeRemaining / interval
        
        // Refresh PIN when window resets
        if pin == "------" || timeRemaining > 29.0 {
            if let secret = try? KeychainManager.getSecret(for: account.secretReference) {
                if let newPin = try? TOTPGenerator.generatePIN(secret: secret) {
                    pin = newPin
                } else {
                    pin = "ERR"
                }
            } else {
                pin = "N/A"
            }
        }
    }
    
    private func copyToClipboard() {
        guard pin != "------" && pin != "ERR" && pin != "N/A" else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(pin.replacingOccurrences(of: " ", with: ""), forType: .string)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopied = false
            }
        }
    }
}
